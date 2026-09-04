#if canImport(Combine)
import Combine
#endif
import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public private(set) var feed: [BeerLog] = []
    @Published public private(set) var viewedBeerIds: Set<String> = []
    @Published public private(set) var cheersedBeerIds: Set<String> = []
    @Published public private(set) var isLogging = false
    @Published public var errorMessage: String?

    private let service: any BeerServicing
    private let now: () -> Date
    private var isObserving = false

    public init(service: any BeerServicing, now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    public func start() async {
        guard !isObserving else { return }
        isObserving = true
        defer { isObserving = false }
        viewedBeerIds = (try? await service.viewedBeerIds()) ?? []
        do {
            for try await logs in service.observeFeed() {
                let cutoff = now()
                // Full replace: an optimistic logBeer/cheers value may flicker until the
                // listener catches up — accepted v1 tradeoff.
                feed = logs.filter { $0.expiresAt > cutoff }.sorted { $0.createdAt > $1.createdAt }
            }
        } catch {
            errorMessage = "Lost connection to your feed."
        }
    }

    public func logBeer(photoJPEG: Data?) async {
        guard !isLogging else { return }
        isLogging = true
        defer { isLogging = false }
        do {
            let log = try await service.logBeer(photoJPEG: photoJPEG)
            feed.insert(log, at: 0)
        } catch {
            errorMessage = "Couldn't log your beer — try again."
        }
    }

    public func cheers(_ beer: BeerLog) async {
        guard !cheersedBeerIds.contains(beer.id) else { return }
        cheersedBeerIds.insert(beer.id)
        if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].cheersCount += 1 }
        do {
            try await service.cheers(beerId: beer.id)
        } catch {
            cheersedBeerIds.remove(beer.id)
            if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].cheersCount -= 1 }
            errorMessage = "Couldn't send your cheers — try again."
        }
    }

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
