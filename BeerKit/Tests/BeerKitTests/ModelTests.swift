import Foundation
import Testing
@testable import BeerKit

@Suite struct ModelTests {
    @Test func beerLogRoundTripsJSON() throws {
        let log = BeerLog(id: "b1", ownerUid: "u1", ownerName: "Tim",
                          createdAt: Date(timeIntervalSince1970: 1000),
                          expiresAt: Date(timeIntervalSince1970: 1000 + 86400),
                          hasPhoto: true, cheersCount: 2)
        let data = try JSONEncoder().encode(log)
        #expect(try JSONDecoder().decode(BeerLog.self, from: data) == log)
    }
    @Test func expiryIs24h() {
        let created = Date(timeIntervalSince1970: 0)
        #expect(BeerLog.expiry(from: created) == created.addingTimeInterval(24 * 3600))
    }
}
