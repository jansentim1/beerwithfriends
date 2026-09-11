#if canImport(Combine)
import Combine
#endif
import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public private(set) var feed: [BeerLog] = []
    @Published public private(set) var viewedBeerIds: Set<String> = []
    @Published public private(set) var cheersedBeerIds: Set<String> = []
    /// True while a photo beer is uploading (plain beers never block the button).
    @Published public private(set) var isUploadingPhoto = false
    @Published public var errorMessage: String?

    private let service: any BeerServicing
    private let placeProvider: (any PlaceProviding)?
    private let now: () -> Date
    private let retryDelay: (Int) -> Duration
    private var observation: Task<Void, Never>?
    /// Optimistic rows whose server ack is still outstanding. A snapshot that
    /// predates the local write may omit them; they are re-added until acked.
    private var pendingIds: Set<String> = []
    private var cheersLookupDone: Set<String> = []
    /// Consecutive feed-stream failures (for backoff); reset on a good snapshot.
    private(set) var feedFailures = 0
    /// Minimum time between two of the user's own drinks (mirrored server-side).
    public static let logCooldown: TimeInterval = 60

    public init(
        service: any BeerServicing,
        placeProvider: (any PlaceProviding)? = nil,
        now: @escaping () -> Date = { Date() },
        retryDelay: @escaping (Int) -> Duration = { attempt in .seconds(min(2 << attempt, 30)) }
    ) {
        self.service = service
        self.placeProvider = placeProvider
        self.now = now
        self.retryDelay = retryDelay
    }

    // MARK: - Feed

    /// Subscribes to the feed (restarting any previous subscription first) and
    /// runs until cancelled. Bind it to a SwiftUI `.task(id:)`: changing the id
    /// cancels the old call and the new one awaits the old stream's teardown
    /// before subscribing, so there is never a window with zero listeners.
    public func start() async {
        if let previous = observation {
            previous.cancel()
            await previous.value
        }
        let task = Task { await observe() }
        observation = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if observation == task { observation = nil }
    }

    private func observe() async {
        // Off the critical path: the feed subscribes immediately, view state
        // fills in when it arrives.
        let viewedTask = Task { [service] in (try? await service.viewedBeerIds()) ?? [] }
        Task { [weak self] in
            let ids = await viewedTask.value
            guard let self, !Task.isCancelled else { return }
            self.viewedBeerIds.formUnion(ids)
        }
        while !Task.isCancelled {
            do {
                for try await logs in service.observeFeed() {
                    feedFailures = 0
                    apply(snapshot: logs)
                }
                return // stream ended normally (cancellation)
            } catch {
                if Task.isCancelled { return }
                feedFailures += 1
                if feedFailures >= 3 {
                    errorMessage = "Lost connection to your feed."
                }
                // Resubscribing also re-snapshots the friend list (new friends,
                // severed friendships) — the fix for permission-denied streams.
                try? await Task.sleep(for: retryDelay(feedFailures - 1))
            }
        }
    }

    private func apply(snapshot logs: [BeerLog]) {
        var merged = logs
        let present = Set(merged.map(\.id))
        // Keep optimistic rows the snapshot doesn't know about yet.
        for beer in feed where pendingIds.contains(beer.id) && !present.contains(beer.id) {
            merged.append(beer)
        }
        // One row per person (their newest), alive ones only, newest first.
        feed = BeerLog.latestPerOwner(merged, now: now())
        loadCheersState(for: feed.map(\.id))
    }

    private func loadCheersState(for ids: [String]) {
        let fresh = ids.filter { !cheersLookupDone.contains($0) }
        guard !fresh.isEmpty else { return }
        cheersLookupDone.formUnion(fresh)
        Task { [service, weak self] in
            guard let found = try? await service.cheersedBeerIds(among: fresh) else { return }
            self?.cheersedBeerIds.formUnion(found)
        }
    }

    // MARK: - Anti-spam

    /// The user's most recent drink in the feed (optimistic rows included).
    public func latestOwnDrink(myUid: String) -> BeerLog? {
        feed.filter { $0.ownerUid == myUid }.max { $0.createdAt < $1.createdAt }
    }

    /// Seconds until the next drink may be logged; 0 when free.
    public func cooldownRemaining(myUid: String) -> TimeInterval {
        guard let last = latestOwnDrink(myUid: myUid) else { return 0 }
        return max(0, Self.logCooldown - now().timeIntervalSince(last.createdAt))
    }

    // MARK: - Log a beer

    /// Optimistic: the row is in the feed before any network round-trip. Only a
    /// photo upload blocks the button (a second photo mid-upload makes no sense).
    /// Returns false (and logs nothing) while the cooldown after the previous
    /// drink is still running; the picker shakes instead.
    @discardableResult
    public func logBeer(photoJPEG: Data?, drink: DrinkKind = .pils, myUid: String? = nil) async -> Bool {
        if let myUid, cooldownRemaining(myUid: myUid) > 0 { return false }
        if photoJPEG != nil {
            guard !isUploadingPhoto else { return false }
            isUploadingPhoto = true
        }
        defer { if photoJPEG != nil { isUploadingPhoto = false } }

        var beer = service.newBeerLog(hasPhoto: photoJPEG != nil, drink: drink)
        pendingIds.insert(beer.id)
        upsert(beer)
        // Opt-in place lookup runs AFTER the row is visible; beers are immutable
        // server-side, so the place must be known before the write.
        if let placeProvider, let place = await placeProvider.currentPlace() {
            beer.place = String(place.name.prefix(BeerLog.placeMaxLength))
            beer.placeCoordinate = place.coordinate
            upsert(beer)
        }
        do {
            try await service.logBeer(beer, photoJPEG: photoJPEG)
            pendingIds.remove(beer.id)
            return true
        } catch {
            pendingIds.remove(beer.id)
            feed.removeAll { $0.id == beer.id }
            errorMessage = "Couldn't log your beer — try again."
            return false
        }
    }

    private func upsert(_ beer: BeerLog) {
        if let i = feed.firstIndex(where: { $0.id == beer.id }) {
            feed[i] = beer
        } else {
            feed.insert(beer, at: 0)
            feed.sort { $0.createdAt > $1.createdAt }
        }
    }

    // MARK: - Cheers

    public func cheers(_ beer: BeerLog) async {
        guard !cheersedBeerIds.contains(beer.id) else { return }
        cheersedBeerIds.insert(beer.id)
        if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].cheersCount += 1 }
        do {
            try await service.cheers(beerId: beer.id)
        } catch CheersError.alreadyCheersed {
            // Server already has it (e.g. cheersed before a reinstall): keep the
            // mark, undo only the optimistic +1.
            if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].cheersCount -= 1 }
        } catch {
            cheersedBeerIds.remove(beer.id)
            if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].cheersCount -= 1 }
            errorMessage = "Couldn't send your cheers — try again."
        }
    }

    // MARK: - Quick replies

    /// Optimistic like cheers; the server echoes the reply into `beer.replies`.
    public func reply(_ beer: BeerLog, kind: ReplyKind, myUid: String) async {
        guard beer.replies[myUid] == nil else { return }
        if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].replies[myUid] = kind }
        do {
            try await service.reply(beerId: beer.id, kind: kind)
        } catch CheersError.alreadyCheersed {
            // Already replied earlier (create-only): keep whatever the server has.
        } catch {
            if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].replies[myUid] = nil }
            errorMessage = "Couldn't send your reply — try again."
        }
    }

    // MARK: - View-once photo

    public func openPhoto(_ beer: BeerLog) async -> URL? {
        do {
            let url = try await service.fetchPhotoOnce(beerId: beer.id)
            viewedBeerIds.insert(beer.id)
            return url
        } catch PhotoFetchError.alreadyViewed {
            viewedBeerIds.insert(beer.id)
            errorMessage = "You already used your one view 👀"
            return nil
        } catch PhotoFetchError.expired {
            errorMessage = "This photo has expired."
            return nil
        } catch PhotoFetchError.notFriends {
            errorMessage = "You're no longer friends with this person."
            return nil
        } catch {
            errorMessage = "Couldn't open the photo."
            return nil
        }
    }
}
