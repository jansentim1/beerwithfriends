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
    private let now: () -> Date
    private let retryDelay: (Int) -> Duration
    private var observation: Task<Void, Never>?
    /// Optimistic rows whose server ack is still outstanding. A snapshot that
    /// predates the local write may omit them; they are re-added until acked.
    private var pendingIds: Set<String> = []
    private var cheersLookupDone: Set<String> = []
    /// Consecutive feed-stream failures (for backoff); reset on a good snapshot.
    private(set) var feedFailures = 0

    public init(
        service: any BeerServicing,
        now: @escaping () -> Date = { Date() },
        retryDelay: @escaping (Int) -> Duration = { attempt in .seconds(min(2 << attempt, 30)) }
    ) {
        self.service = service
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
        let cutoff = now()
        var merged = logs.filter { $0.expiresAt > cutoff }
        let present = Set(merged.map(\.id))
        // Keep optimistic rows the snapshot doesn't know about yet.
        for beer in feed where pendingIds.contains(beer.id) && !present.contains(beer.id) {
            merged.append(beer)
        }
        feed = merged.sorted { $0.createdAt > $1.createdAt }
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

    // MARK: - Log a beer

    /// Optimistic: the row is in the feed before any network round-trip. Only a
    /// photo upload blocks the button (a second photo mid-upload makes no sense).
    public func logBeer(photoJPEG: Data?) async {
        if photoJPEG != nil {
            guard !isUploadingPhoto else { return }
            isUploadingPhoto = true
        }
        defer { if photoJPEG != nil { isUploadingPhoto = false } }

        let beer = service.newBeerLog(hasPhoto: photoJPEG != nil)
        pendingIds.insert(beer.id)
        upsert(beer)
        do {
            try await service.logBeer(beer, photoJPEG: photoJPEG)
            pendingIds.remove(beer.id)
        } catch {
            pendingIds.remove(beer.id)
            feed.removeAll { $0.id == beer.id }
            errorMessage = "Couldn't log your beer — try again."
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
