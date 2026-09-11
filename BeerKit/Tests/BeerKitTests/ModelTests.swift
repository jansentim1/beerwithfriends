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
    @Test func expiryIsTwoHours() {
        let created = Date(timeIntervalSince1970: 0)
        #expect(BeerLog.expiry(from: created) == created.addingTimeInterval(2 * 3600))
        #expect(BeerLog.lifetime == 2 * 3600)
    }

    @Test func latestPerOwnerKeepsOneLiveDrinkPerPerson() {
        func beer(_ id: String, _ owner: String, at t: TimeInterval, life: TimeInterval = 2 * 3600) -> BeerLog {
            BeerLog(id: id, ownerUid: owner, ownerName: owner, createdAt: Date(timeIntervalSince1970: t),
                    expiresAt: Date(timeIntervalSince1970: t + life), hasPhoto: false)
        }
        let now = Date(timeIntervalSince1970: 10_000)
        let logs = [
            beer("a1", "a", at: 1_000),          // superseded by a2
            beer("a2", "a", at: 5_000),
            beer("b1", "b", at: 9_000),
            beer("c1", "c", at: 2_000, life: 1_000), // expired
            beer("a3", "a", at: 6_000, life: 1_000), // newest of a, but expired
        ]
        let shown = BeerLog.latestPerOwner(logs, now: now)
        #expect(shown.map(\.id) == ["b1", "a2"])
    }

    @Test func displayNameNormalizes() {
        #expect(DisplayName.normalize("  Timmy   J\n") == "Timmy J")
        #expect(DisplayName.normalize("   ") == nil)
        #expect(DisplayName.normalize(String(repeating: "x", count: 31)) == nil)
        #expect(DisplayName.normalize(String(repeating: "x", count: 30)) != nil)
    }
}
