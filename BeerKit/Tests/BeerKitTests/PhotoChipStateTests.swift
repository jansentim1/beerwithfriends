import Foundation
import Testing
@testable import BeerKit

@Suite struct PhotoChipStateTests {
    let t0 = Date(timeIntervalSince1970: 0)
    func log(hasPhoto: Bool) -> BeerLog {
        BeerLog(id: "b", ownerUid: "u", ownerName: "n", createdAt: t0,
                expiresAt: BeerLog.expiry(from: t0), hasPhoto: hasPhoto)
    }
    @Test func noPhoto() { #expect(log(hasPhoto: false).photoChipState(viewedByMe: false, now: t0) == .none) }
    @Test func sealed() { #expect(log(hasPhoto: true).photoChipState(viewedByMe: false, now: t0) == .sealed) }
    @Test func seen() { #expect(log(hasPhoto: true).photoChipState(viewedByMe: true, now: t0) == .seen) }
    @Test func expired() {
        let later = t0.addingTimeInterval(24 * 3600)
        #expect(log(hasPhoto: true).photoChipState(viewedByMe: false, now: later) == .expired)
    }
}
