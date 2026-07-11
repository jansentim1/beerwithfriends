import Foundation
import Testing
@testable import BeerKit

final class FakeBeerService: BeerServicing, @unchecked Sendable {
    var logged: [Data?] = []
    var cheersed: [String] = []
    var cheersError: Error?
    var photoResult: Result<URL, Error> = .success(URL(string: "https://x.test/p.jpg")!)
    var feedContinuation: AsyncThrowingStream<[BeerLog], Error>.Continuation?
    func logBeer(photoJPEG: Data?) async throws -> BeerLog {
        logged.append(photoJPEG)
        let now = Date(timeIntervalSince1970: 500)
        return BeerLog(id: "new", ownerUid: "me", ownerName: "Me", createdAt: now,
                       expiresAt: BeerLog.expiry(from: now), hasPhoto: photoJPEG != nil)
    }
    func observeFeed() -> AsyncThrowingStream<[BeerLog], Error> {
        AsyncThrowingStream { self.feedContinuation = $0 }
    }
    func cheers(beerId: String) async throws {
        if let cheersError { throw cheersError }
        cheersed.append(beerId)
    }
    func fetchPhotoOnce(beerId: String) async throws -> URL { try photoResult.get() }
    func viewedBeerIds() async throws -> Set<String> { ["seen1"] }
}

func makeBeer(_ id: String, createdAt: TimeInterval, hasPhoto: Bool = false) -> BeerLog {
    let t = Date(timeIntervalSince1970: createdAt)
    return BeerLog(id: id, ownerUid: "u2", ownerName: "Joost", createdAt: t,
                   expiresAt: BeerLog.expiry(from: t), hasPhoto: hasPhoto)
}

@Suite struct HomeViewModelTests {
    @Test @MainActor func logBeerAppendsToFeed() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        await vm.logBeer(photoJPEG: nil)
        #expect(svc.logged.count == 1)
        #expect(vm.feed.first?.id == "new")
    }
    @Test @MainActor func openPhotoMarksViewed() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let t0 = Date(timeIntervalSince1970: 400)
        let beer = BeerLog(id: "b1", ownerUid: "u2", ownerName: "Joost", createdAt: t0,
                           expiresAt: BeerLog.expiry(from: t0), hasPhoto: true)
        let url = await vm.openPhoto(beer)
        #expect(url != nil)
        #expect(vm.viewedBeerIds.contains("b1"))
    }
    @Test @MainActor func startLoadsViewedIdsFiltersExpiredAndSorts() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 200_000) })
        let running = Task { await vm.start() }
        while svc.feedContinuation == nil { await Task.yield() }
        let expired = makeBeer("expired", createdAt: 100_000)   // expires at 186_400 < now
        let older = makeBeer("older", createdAt: 150_000)
        let newer = makeBeer("newer", createdAt: 190_000)
        svc.feedContinuation?.yield([expired, older, newer])
        svc.feedContinuation?.finish()
        await running.value
        #expect(vm.feed.map(\.id) == ["newer", "older"])
        #expect(vm.viewedBeerIds == ["seen1"])
    }
    @Test @MainActor func startFeedErrorSetsMessage() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let running = Task { await vm.start() }
        while svc.feedContinuation == nil { await Task.yield() }
        svc.feedContinuation?.finish(throwing: PhotoFetchError.notFound)
        await running.value
        #expect(vm.errorMessage != nil)
    }
    @Test @MainActor func cheersIsOptimisticAndIdempotent() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let beer = makeBeer("b1", createdAt: 400)
        await vm.cheers(beer)
        await vm.cheers(beer)  // duplicate tap ignored
        #expect(svc.cheersed == ["b1"])
        #expect(vm.cheersedBeerIds == ["b1"])
    }
    @Test @MainActor func cheersFailureRollsBack() async {
        let svc = FakeBeerService()
        svc.cheersError = PhotoFetchError.notFound
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        await vm.cheers(makeBeer("b1", createdAt: 400))
        #expect(vm.cheersedBeerIds.isEmpty)
        #expect(vm.errorMessage != nil)
    }
    @Test @MainActor func openPhotoAlreadyViewedSetsError() async {
        let svc = FakeBeerService()
        svc.photoResult = .failure(PhotoFetchError.alreadyViewed)
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let t0 = Date(timeIntervalSince1970: 400)
        let beer = BeerLog(id: "b1", ownerUid: "u2", ownerName: "Joost", createdAt: t0,
                           expiresAt: BeerLog.expiry(from: t0), hasPhoto: true)
        let url = await vm.openPhoto(beer)
        #expect(url == nil)
        #expect(vm.errorMessage != nil)
    }
}
