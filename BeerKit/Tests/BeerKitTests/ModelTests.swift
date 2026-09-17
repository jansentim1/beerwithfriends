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
    @Test func expiryIsTheOneDayHardCap() {
        let created = Date(timeIntervalSince1970: 0)
        #expect(BeerLog.expiry(from: created) == created.addingTimeInterval(24 * 3600))
        #expect(BeerLog.lifetime == 24 * 3600)
        #expect(BeerLog.seenLifetime == 2 * 3600)
    }

    @Test func anUnseenDrinkStaysAndASeenOneFadesAfterTwoHours() {
        let t0 = Date(timeIntervalSince1970: 0)
        let beer = BeerLog(id: "b", ownerUid: "u", ownerName: "u", createdAt: t0,
                           expiresAt: BeerLog.expiry(from: t0), hasPhoto: false)
        // Never seen: still there twenty hours on.
        #expect(!beer.hasFaded(seenAt: nil, now: t0.addingTimeInterval(20 * 3600)))
        // Seen at t0: gone at two hours, there at one.
        #expect(!beer.hasFaded(seenAt: t0, now: t0.addingTimeInterval(3600)))
        #expect(beer.hasFaded(seenAt: t0, now: t0.addingTimeInterval(2 * 3600)))
        // Seen late still gets its full two hours, but never past the hard cap.
        let late = t0.addingTimeInterval(23 * 3600)
        #expect(!beer.hasFaded(seenAt: late, now: late.addingTimeInterval(1800)))
        #expect(beer.hasFaded(seenAt: late, now: t0.addingTimeInterval(24 * 3600)))
    }

    @Test func latestPerOwnerHonoursTheSeenClock() {
        let t0 = Date(timeIntervalSince1970: 0)
        func b(_ id: String, _ owner: String, at s: TimeInterval) -> BeerLog {
            BeerLog(id: id, ownerUid: owner, ownerName: owner,
                    createdAt: t0.addingTimeInterval(s),
                    expiresAt: t0.addingTimeInterval(s + 24 * 3600), hasPhoto: false)
        }
        let now = t0.addingTimeInterval(5 * 3600)
        let logs = [b("seen", "a", at: 0), b("unseen", "b", at: 60)]
        // a's drink was seen three hours ago, b's never.
        let shown = BeerLog.latestPerOwner(logs, now: now,
                                           seenAt: ["seen": t0.addingTimeInterval(2 * 3600)])
        #expect(shown.map(\.id) == ["unseen"])
    }

    @Test func latestPerOwnerKeepsOneLiveDrinkPerPerson() {
        func beer(_ id: String, _ owner: String, at t: TimeInterval, life: TimeInterval = 3600) -> BeerLog {
            BeerLog(id: id, ownerUid: owner, ownerName: owner, createdAt: Date(timeIntervalSince1970: t),
                    expiresAt: Date(timeIntervalSince1970: t + life), hasPhoto: false)
        }
        let now = Date(timeIntervalSince1970: 10_000)
        let logs = [
            beer("a1", "a", at: 6_500),          // superseded by a2
            beer("a2", "a", at: 7_000),
            beer("b1", "b", at: 9_000),
            beer("c1", "c", at: 2_000, life: 1_000), // expired
            beer("a3", "a", at: 6_000, life: 1_000), // newest of a, but expired
        ]
        let shown = BeerLog.latestPerOwner(logs, now: now)
        #expect(shown.map(\.id) == ["b1", "a2"])
    }

    @Test func reactionsListCheersThenRepliesSortedByName() {
        let beer = BeerLog(
            id: "b1", ownerUid: "me", ownerName: "Me",
            createdAt: Date(timeIntervalSince1970: 0),
            expiresAt: Date(timeIntervalSince1970: 3600), hasPhoto: false, cheersCount: 3,
            replies: ["u4": .onMyWay, "u5": .jealous],
            cheersBy: ["u2": "Menno", "u1": "daan", "u3": "Joost"],
            replyNames: ["u4": "Gijs"]   // u5's name never mirrored
        )
        let r = beer.reactions
        #expect(r.cheers.map(\.name) == ["daan", "Joost", "Menno"])   // case-insensitive
        #expect(r.cheers.allSatisfy { $0.reply == nil })
        #expect(r.replies.map(\.name) == ["a mate", "Gijs"])          // fallback sorts as its name
        #expect(r.replies.map(\.reply) == [.jealous, .onMyWay])
        #expect(r.cheersCount == 3)
        #expect(!r.isEmpty)
    }

    @Test func reactionsAreEmptyWithoutMirrors() {
        let beer = BeerLog(id: "b1", ownerUid: "me", ownerName: "Me",
                           createdAt: Date(timeIntervalSince1970: 0),
                           expiresAt: Date(timeIntervalSince1970: 3600), hasPhoto: false,
                           cheersCount: 2)   // counter ahead of the names
        #expect(beer.reactions.isEmpty)
        #expect(beer.reactions.cheersCount == 0)
    }

    @Test func displayNameNormalizes() {
        #expect(DisplayName.normalize("  Timmy   J\n") == "Timmy J")
        #expect(DisplayName.normalize("   ") == nil)
        #expect(DisplayName.normalize(String(repeating: "x", count: 31)) == nil)
        #expect(DisplayName.normalize(String(repeating: "x", count: 30)) != nil)
    }
}
