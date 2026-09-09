import Foundation
import Testing
@testable import BeerKit

final class FakeBeerService: BeerServicing, @unchecked Sendable {
    var logged: [(BeerLog, Data?)] = []
    var logError: Error?
    /// Set to hold `logBeer` until released (simulates a slow server ack).
    var logGate: CheckedContinuation<Void, Never>?
    var holdLog = false
    var cheersed: [String] = []
    var cheersError: Error?
    var photoResult: Result<URL, Error> = .success(URL(string: "https://x.test/p.jpg")!)
    var viewed: Set<String> = ["seen1"]
    var viewedDelayNs: UInt64 = 0
    var cheersedOnServer: Set<String> = []
    var cheersLookups: [[String]] = []
    var observeCount = 0
    var terminations = 0
    var feedContinuation: AsyncThrowingStream<[BeerLog], Error>.Continuation?
    var nextId = 0

    func newBeerLog(hasPhoto: Bool) -> BeerLog {
        nextId += 1
        let now = Date(timeIntervalSince1970: 500 + Double(nextId))
        return BeerLog(id: "new\(nextId)", ownerUid: "me", ownerName: "Me", createdAt: now,
                       expiresAt: BeerLog.expiry(from: now), hasPhoto: hasPhoto)
    }
    func logBeer(_ beer: BeerLog, photoJPEG: Data?) async throws {
        logged.append((beer, photoJPEG))
        if holdLog {
            await withCheckedContinuation { logGate = $0 }
        }
        if let logError { throw logError }
    }
    func observeFeed() -> AsyncThrowingStream<[BeerLog], Error> {
        observeCount += 1
        return AsyncThrowingStream { continuation in
            self.feedContinuation = continuation
            continuation.onTermination = { _ in self.terminations += 1 }
        }
    }
    func cheers(beerId: String) async throws {
        if let cheersError { throw cheersError }
        cheersed.append(beerId)
    }
    var replies: [(String, ReplyKind)] = []
    var replyError: Error?
    func reply(beerId: String, kind: ReplyKind) async throws {
        if let replyError { throw replyError }
        replies.append((beerId, kind))
    }
    func fetchPhotoOnce(beerId: String) async throws -> URL { try photoResult.get() }
    func viewedBeerIds() async throws -> Set<String> {
        if viewedDelayNs > 0 { try? await Task.sleep(nanoseconds: viewedDelayNs) }
        return viewed
    }
    func cheersedBeerIds(among beerIds: [String]) async throws -> Set<String> {
        cheersLookups.append(beerIds)
        return cheersedOnServer.intersection(beerIds)
    }
}

func makeBeer(_ id: String, createdAt: TimeInterval, hasPhoto: Bool = false) -> BeerLog {
    let t = Date(timeIntervalSince1970: createdAt)
    return BeerLog(id: id, ownerUid: "u2", ownerName: "Joost", createdAt: t,
                   expiresAt: BeerLog.expiry(from: t), hasPhoto: hasPhoto)
}

@MainActor
func startAndWaitForSubscription(_ vm: HomeViewModel, _ svc: FakeBeerService) async -> Task<Void, Never> {
    let before = svc.observeCount
    let running = Task { await vm.start() }
    while svc.observeCount == before || svc.feedContinuation == nil { await Task.yield() }
    return running
}

@MainActor
func waitForFeed(_ vm: HomeViewModel) async {
    for _ in 0..<200 where vm.feed.isEmpty { await Task.yield() }
}

@Suite struct HomeViewModelTests {
    let now = { Date(timeIntervalSince1970: 500) }

    // MARK: Logging

    @Test @MainActor func logBeerShowsRowBeforeServerAck() async {
        let svc = FakeBeerService()
        svc.holdLog = true
        let vm = HomeViewModel(service: svc, now: now)
        let logging = Task { await vm.logBeer(photoJPEG: nil) }
        while svc.logGate == nil { await Task.yield() }
        #expect(vm.feed.first?.id == "new1")           // visible while the write is in flight
        #expect(vm.isUploadingPhoto == false)          // plain beers never block the button
        svc.logGate?.resume()
        await logging.value
        #expect(vm.feed.map(\.id) == ["new1"])
    }

    @Test @MainActor func logBeerFailureRemovesRowAndReports() async {
        let svc = FakeBeerService()
        svc.logError = PhotoFetchError.notFound
        let vm = HomeViewModel(service: svc, now: now)
        await vm.logBeer(photoJPEG: nil)
        #expect(vm.feed.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test @MainActor func snapshotWithSameIdDoesNotDuplicate() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: now)
        let running = await startAndWaitForSubscription(vm, svc)
        await vm.logBeer(photoJPEG: nil)
        let fromServer = vm.feed[0]
        svc.feedContinuation?.yield([fromServer, makeBeer("b1", createdAt: 400)])
        await Task.yield(); await Task.yield()
        #expect(vm.feed.map(\.id) == ["new1", "b1"])
        running.cancel(); await running.value
    }

    @Test @MainActor func pendingRowSurvivesStaleSnapshot() async {
        let svc = FakeBeerService()
        svc.holdLog = true
        let vm = HomeViewModel(service: svc, now: now)
        let running = await startAndWaitForSubscription(vm, svc)
        let logging = Task { await vm.logBeer(photoJPEG: nil) }
        while svc.logGate == nil { await Task.yield() }
        svc.feedContinuation?.yield([makeBeer("b1", createdAt: 400)]) // predates the local write
        await Task.yield(); await Task.yield()
        #expect(vm.feed.map(\.id) == ["new1", "b1"])
        svc.logGate?.resume()
        await logging.value
        running.cancel(); await running.value
    }

    @Test @MainActor func photoUploadBlocksSecondPhotoOnly() async {
        let svc = FakeBeerService()
        svc.holdLog = true
        let vm = HomeViewModel(service: svc, now: now)
        let first = Task { await vm.logBeer(photoJPEG: Data([1])) }
        while svc.logGate == nil { await Task.yield() }
        #expect(vm.isUploadingPhoto)
        await vm.logBeer(photoJPEG: Data([2]))         // ignored while uploading
        #expect(svc.logged.count == 1)
        svc.logGate?.resume()
        await first.value
        #expect(vm.isUploadingPhoto == false)
    }

    // MARK: Feed lifecycle

    @Test @MainActor func startSubscribesBeforeViewedIdsResolve() async {
        let svc = FakeBeerService()
        svc.viewedDelayNs = 200_000_000
        let vm = HomeViewModel(service: svc, now: now)
        let running = await startAndWaitForSubscription(vm, svc)
        #expect(vm.viewedBeerIds.isEmpty)              // feed is live, view state still loading
        svc.feedContinuation?.yield([makeBeer("b1", createdAt: 400)])
        await Task.yield(); await Task.yield()
        #expect(vm.feed.map(\.id) == ["b1"])
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.viewedBeerIds == ["seen1"])
        running.cancel(); await running.value
    }

    @Test @MainActor func startFiltersExpiredAndSorts() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 200_000) })
        let running = await startAndWaitForSubscription(vm, svc)
        let expired = makeBeer("expired", createdAt: 100_000)   // expires at 186_400 < now
        let older = makeBeer("older", createdAt: 150_000)
        let newer = makeBeer("newer", createdAt: 190_000)
        svc.feedContinuation?.yield([expired, older, newer])
        await Task.yield(); await Task.yield()
        #expect(vm.feed.map(\.id) == ["newer", "older"])
        running.cancel(); await running.value
    }

    @Test @MainActor func restartTearsDownPreviousStreamFirst() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: now)
        let first = await startAndWaitForSubscription(vm, svc)
        first.cancel()
        let second = await startAndWaitForSubscription(vm, svc)
        #expect(svc.observeCount == 2)
        #expect(svc.terminations >= 1)                 // old listener removed, not leaked
        second.cancel(); await second.value
        #expect(svc.terminations == 2)
    }

    @Test @MainActor func streamErrorResubscribesSilently() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: now, retryDelay: { _ in .milliseconds(1) })
        let running = await startAndWaitForSubscription(vm, svc)
        svc.feedContinuation?.finish(throwing: PhotoFetchError.notFound)
        while svc.observeCount < 2 { await Task.yield() }
        #expect(vm.errorMessage == nil)                // one hiccup is not an alert
        #expect(svc.observeCount == 2)
        running.cancel(); await running.value
    }

    @Test @MainActor func repeatedStreamErrorsSurfaceAfterThree() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: now, retryDelay: { _ in .milliseconds(1) })
        let running = await startAndWaitForSubscription(vm, svc)
        for n in 2...4 {
            svc.feedContinuation?.finish(throwing: PhotoFetchError.notFound)
            while svc.observeCount < n { await Task.yield() }
        }
        #expect(vm.errorMessage != nil)
        running.cancel(); await running.value
    }

    // MARK: Cheers

    @Test @MainActor func cheersStateLoadsForFeedBeers() async {
        let svc = FakeBeerService()
        svc.cheersedOnServer = ["b1"]
        let vm = HomeViewModel(service: svc, now: now)
        let running = await startAndWaitForSubscription(vm, svc)
        svc.feedContinuation?.yield([makeBeer("b1", createdAt: 400), makeBeer("b2", createdAt: 300)])
        for _ in 0..<10 { await Task.yield() }
        #expect(vm.cheersedBeerIds == ["b1"])
        #expect(svc.cheersLookups == [["b1", "b2"]])
        svc.feedContinuation?.yield([makeBeer("b1", createdAt: 400), makeBeer("b2", createdAt: 300)])
        for _ in 0..<5 { await Task.yield() }
        #expect(svc.cheersLookups.count == 1)          // no re-lookup for known ids
        running.cancel(); await running.value
    }

    @Test @MainActor func cheersIsOptimisticAndIdempotent() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: now)
        let beer = makeBeer("b1", createdAt: 400)
        await vm.cheers(beer)
        await vm.cheers(beer)  // duplicate tap ignored
        #expect(svc.cheersed == ["b1"])
        #expect(vm.cheersedBeerIds == ["b1"])
    }

    @Test @MainActor func cheersFailureRollsBack() async {
        let svc = FakeBeerService()
        svc.cheersError = PhotoFetchError.notFound
        let vm = HomeViewModel(service: svc, now: now)
        await vm.cheers(makeBeer("b1", createdAt: 400))
        #expect(vm.cheersedBeerIds.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test @MainActor func cheersAlreadyOnServerKeepsMark() async {
        let svc = FakeBeerService()
        svc.cheersError = CheersError.alreadyCheersed
        let vm = HomeViewModel(service: svc, now: now)
        let running = await startAndWaitForSubscription(vm, svc)
        svc.feedContinuation?.yield([makeBeer("b1", createdAt: 400)])
        await waitForFeed(vm)
        await vm.cheers(vm.feed[0])
        #expect(vm.cheersedBeerIds == ["b1"])
        #expect(vm.feed[0].cheersCount == 0)           // optimistic +1 undone
        #expect(vm.errorMessage == nil)
        running.cancel(); await running.value
    }

    // MARK: Photo

    @Test @MainActor func openPhotoMarksViewed() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: now)
        let url = await vm.openPhoto(makeBeer("b1", createdAt: 400, hasPhoto: true))
        #expect(url != nil)
        #expect(vm.viewedBeerIds.contains("b1"))
    }

    @Test @MainActor func openPhotoAlreadyViewedSetsError() async {
        let svc = FakeBeerService()
        svc.photoResult = .failure(PhotoFetchError.alreadyViewed)
        let vm = HomeViewModel(service: svc, now: now)
        let url = await vm.openPhoto(makeBeer("b1", createdAt: 400, hasPhoto: true))
        #expect(url == nil)
        #expect(vm.errorMessage != nil)
    }
}

final class FakePlaces: PlaceProviding, @unchecked Sendable {
    var place: String?
    var delayNs: UInt64 = 0
    func currentPlace() async -> String? {
        if delayNs > 0 { try? await Task.sleep(nanoseconds: delayNs) }
        return place
    }
}

@Suite struct ReplyTests {
    @Test @MainActor func replyIsOptimisticAndOncePerUser() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let running = await startAndWaitForSubscription(vm, svc)
        svc.feedContinuation?.yield([makeBeer("b1", createdAt: 400)])
        await waitForFeed(vm)
        await vm.reply(vm.feed[0], kind: .onMyWay, myUid: "me")
        await vm.reply(vm.feed[0], kind: .jealous, myUid: "me")     // second reply ignored
        #expect(vm.feed[0].replies["me"] == .onMyWay)
        #expect(svc.replies.map(\.1) == [.onMyWay])
        #expect(vm.feed[0].replyCount(.onMyWay) == 1)
        running.cancel(); await running.value
    }
    @Test @MainActor func replyFailureRollsBack() async {
        let svc = FakeBeerService()
        svc.replyError = PhotoFetchError.notFound
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let running = await startAndWaitForSubscription(vm, svc)
        svc.feedContinuation?.yield([makeBeer("b1", createdAt: 400)])
        await waitForFeed(vm)
        await vm.reply(vm.feed[0], kind: .jealous, myUid: "me")
        #expect(vm.feed[0].replies.isEmpty)
        #expect(vm.errorMessage != nil)
        running.cancel(); await running.value
    }
}

@Suite struct PlaceTests {
    @Test @MainActor func rowShowsBeforePlaceResolvesThenCarriesIt() async {
        let svc = FakeBeerService()
        let places = FakePlaces(); places.place = "Café De Zon"; places.delayNs = 100_000_000
        let vm = HomeViewModel(service: svc, placeProvider: places, now: { Date(timeIntervalSince1970: 500) })
        let logging = Task { await vm.logBeer(photoJPEG: nil) }
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(vm.feed.first?.id == "new1")          // visible before the lookup finishes
        #expect(vm.feed.first?.place == nil)
        await logging.value
        #expect(vm.feed.first?.place == "Café De Zon")
        #expect(svc.logged.first?.0.place == "Café De Zon")   // persisted with the place
    }
    @Test @MainActor func noProviderOrNilPlaceLogsWithoutPlace() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, placeProvider: FakePlaces(), now: { Date(timeIntervalSince1970: 500) })
        await vm.logBeer(photoJPEG: nil)
        #expect(svc.logged.first?.0.place == nil)
    }
    @Test @MainActor func placeIsTruncatedToLimit() async {
        let svc = FakeBeerService()
        let places = FakePlaces(); places.place = String(repeating: "x", count: 100)
        let vm = HomeViewModel(service: svc, placeProvider: places, now: { Date(timeIntervalSince1970: 500) })
        await vm.logBeer(photoJPEG: nil)
        #expect(svc.logged.first?.0.place?.count == BeerLog.placeMaxLength)
    }
}

@Suite struct TimeoutTests {
    @Test func returnsValueWhenFast() async {
        let v = await Timeout.run(seconds: 1) { 42 }
        #expect(v == 42)
    }
    @Test func returnsNilWhenSlow() async {
        let v: Int? = await Timeout.run(seconds: 0.05) {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return 1
        }
        #expect(v == nil)
    }
}
