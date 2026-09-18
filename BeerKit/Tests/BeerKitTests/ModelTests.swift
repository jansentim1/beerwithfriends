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
            replies: ["u4": "🏃", "u5": "😩"],
            cheersBy: ["u2": "Menno", "u1": "daan", "u3": "Joost"],
            replyNames: ["u4": "Gijs"]   // u5's name never mirrored
        )
        let r = beer.reactions
        #expect(r.cheers.map(\.name) == ["daan", "Joost", "Menno"])   // case-insensitive
        #expect(r.cheers.allSatisfy { $0.reply == nil })
        #expect(r.replies.map(\.name) == ["a mate", "Gijs"])          // fallback sorts as its name
        #expect(r.replies.map(\.reply) == ["😩", "🏃"])
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

    @Test func reactionNormalizes() {
        #expect(Reaction.normalize("  🔥 ") == "🔥")
        #expect(Reaction.normalize("lekker  man\n") == "lekker man")
        #expect(Reaction.normalize("   ") == nil)
        #expect(Reaction.normalize(String(repeating: "x", count: 40))?.count == 24)
        #expect(Reaction.isAllEmoji("🔥🎉"))
        #expect(!Reaction.isAllEmoji("lekker"))
        // Emoji stay whole; words are clipped so a row cannot be pushed apart.
        #expect(Reaction.short("🔥") == "🔥")
        #expect(Reaction.short("kom janne nu") == "kom janne nu")      // exactly at the limit
        #expect(Reaction.short("kom janne nu!!") == "kom janne n…")
        #expect(Reaction.presets.count == 6)
    }

    @Test func reactionTalliesRankByCountThenName() {
        let beer = BeerLog(id: "b", ownerUid: "u", ownerName: "u",
                           createdAt: Date(timeIntervalSince1970: 0),
                           expiresAt: Date(timeIntervalSince1970: 3600), hasPhoto: false,
                           replies: ["a": "🔥", "b": "🔥", "c": "😂", "d": "lekker"])
        let tallies = beer.reactionTallies
        #expect(tallies.first?.reaction == "🔥")
        #expect(tallies.first?.count == 2)
        // Ties fall back to the reaction itself, so the order never wobbles.
        #expect(tallies.dropFirst().map(\.reaction) == ["lekker", "😂"])
    }

    @Test func captionNormalizes() {
        #expect(Caption.normalize("  eindelijk vrijdag 🍻  ") == "eindelijk vrijdag 🍻")
        #expect(Caption.normalize("   \n  \n ") == nil)
        #expect(Caption.normalize("") == nil)
        // Blank lines top and bottom go; a break in the middle is kept.
        #expect(Caption.normalize("\na\n\nb\n") == "a\n\nb")
        // Caps: three lines, eighty characters.
        #expect(Caption.normalize("a\nb\nc\nd") == "a\nb\nc")
        #expect(Caption.normalize(String(repeating: "x", count: 100))?.count == 80)
        #expect(Caption.clampWhileTyping("a\nb\nc\nd") == "a\nb\nc")
        #expect(Caption.clampWhileTyping(String(repeating: "x", count: 90)).count == 80)
    }

    @Test func captionLayoutStaysOnThePhoto() {
        let size = CGSize(width: 810, height: 1080)
        // Dragged off the top: the strip is pushed back fully onto the photo.
        let high = CaptionLayout(lineCount: 1, centre: -0.5)
        #expect(high.stripTop >= 0)
        let low = CaptionLayout(lineCount: 3, centre: 1.5)
        #expect(low.stripTop + low.stripHeight <= 1.0001)
        // More lines, taller strip; the type size does not change.
        let one = CaptionLayout(lineCount: 1, centre: 0.5)
        let three = CaptionLayout(lineCount: 3, centre: 0.5)
        #expect(three.stripHeight > one.stripHeight)
        #expect(three.fontSize(in: size) == one.fontSize(in: size))
        // Full width, and the type scales with the photo.
        #expect(one.stripRect(in: size).width == size.width)
        #expect(one.fontSize(in: size) > one.fontSize(in: CGSize(width: 405, height: 540)))
        #expect(CaptionLayout.stripOpacity == 0.5)
    }

    @Test func displayNameNormalizes() {
        #expect(DisplayName.normalize("  Timmy   J\n") == "Timmy J")
        #expect(DisplayName.normalize("   ") == nil)
        #expect(DisplayName.normalize(String(repeating: "x", count: 31)) == nil)
        #expect(DisplayName.normalize(String(repeating: "x", count: 30)) != nil)
    }
}
