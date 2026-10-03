import Foundation
import Testing
@testable import BeerKit

final class FakeGroups: GroupServicing, @unchecked Sendable {
    var continuation: AsyncThrowingStream<[GroupSummary], Error>.Continuation?
    var created: [String] = []
    var joined: [String] = []
    var joinError: Error?
    func observeGroups() -> AsyncThrowingStream<[GroupSummary], Error> {
        AsyncThrowingStream { self.continuation = $0 }
    }
    func members(of groupId: String) async throws -> [GroupMember] { [] }
    func create(name: String) async throws -> GroupSummary {
        created.append(name)
        return GroupSummary(id: "g", name: name, code: "ABC123", memberCount: 1, todayDate: "2026-09-10", todayCount: 0, totalCount: 0, isMine: true)
    }
    func join(code: String) async throws -> GroupSummary {
        if let joinError { throw joinError }
        joined.append(code)
        return GroupSummary(id: "g2", name: "x", memberCount: 2, todayDate: "2026-09-10", todayCount: 0, totalCount: 0, isMine: true)
    }
    func leave(groupId: String) async throws {}
    var notesByGroup: [String: [GroupNote]] = [:]
    var posted: [String] = []
    var deleted: [String] = []
    func notes(of groupId: String) async throws -> [GroupNote] { notesByGroup[groupId] ?? [] }
    func postNote(groupId: String, text: String, displayName: String) async throws { posted.append(text) }
    func deleteNote(groupId: String, noteId: String) async throws { deleted.append(noteId) }
}

@Suite struct GroupsTests {
    let now = { Date(timeIntervalSince1970: 1_789_000_000) } // 2026-09-10 in Amsterdam
    func g(_ id: String, today: Int, total: Int, date: String = "2026-09-10", mine: Bool = false) -> GroupSummary {
        GroupSummary(id: id, name: id, memberCount: 3, todayDate: date, todayCount: today, totalCount: total, isMine: mine)
    }

    @Test func todayIsAmsterdamDate() {
        #expect(GroupDay.today(now: now()) == "2026-09-10")
        // 23:30 UTC on the 10th is already the 11th in Amsterdam (CEST).
        #expect(GroupDay.today(now: Date(timeIntervalSince1970: 1_789_083_000)) == "2026-09-11")
    }

    @Test @MainActor func rankingUsesTodayThenTotalAndTreatsStaleAsZero() async {
        let svc = FakeGroups()
        let vm = LeaderboardViewModel(service: svc, now: now)
        let running = Task { await vm.start() }
        while svc.continuation == nil { await Task.yield() }
        svc.continuation?.yield([
            g("quiet", today: 9, total: 90, date: "2026-09-09"),   // stale: counts as 0 today
            g("busy", today: 4, total: 10),
            g("steady", today: 4, total: 40, mine: true),
            g("new", today: 0, total: 0),
        ])
        for _ in 0..<50 where vm.groups.isEmpty { await Task.yield() }
        #expect(vm.ranked.map(\.id) == ["steady", "busy", "quiet", "new"])
        #expect(vm.rank(of: vm.groups.first { $0.id == "busy" }!) == 2)
        #expect(vm.mine.map(\.id) == ["steady"])
        running.cancel(); await running.value
    }

    @Test @MainActor func createValidatesName() async {
        let svc = FakeGroups()
        let vm = LeaderboardViewModel(service: svc, now: now)
        #expect(await vm.create(name: "   ") == false)
        #expect(await vm.create(name: String(repeating: "x", count: 31)) == false)
        #expect(await vm.create(name: "  De Kroeg  "))
        #expect(svc.created == ["De Kroeg"])
    }

    @Test @MainActor func joinNormalizesCodeAndMapsErrors() async {
        let svc = FakeGroups()
        let vm = LeaderboardViewModel(service: svc, now: now)
        #expect(await vm.join(code: " abc123 "))
        #expect(svc.joined == ["ABC123"])
        svc.joinError = GroupError.notFound
        #expect(await vm.join(code: "zzz") == false)
        #expect(vm.errorMessage?.contains("ZZZ") == true)
    }

    func m(_ id: String, today: Int, total: Int, date: String = "2026-09-10", name: String? = nil) -> GroupMember {
        GroupMember(id: id, username: id, displayName: name ?? id, joinedAt: Date(timeIntervalSince1970: 0),
                    todayDate: date, todayCount: today, totalCount: total)
    }

    @Test func memberRankingMatchesTheGroupLeaderboardOrder() {
        let ranking = GroupMemberRanking([
            m("quiet", today: 9, total: 90, date: "2026-09-09"),  // stale: counts as 0 today
            m("busy", today: 4, total: 10),
            m("steady", today: 4, total: 40),
            m("new", today: 0, total: 0),
        ], today: "2026-09-10")
        #expect(ranking.members.map(\.id) == ["steady", "busy", "quiet", "new"])
        #expect(ranking.rank(of: "steady") == 1)
        #expect(ranking.rank(of: "busy") == 2)
        #expect(ranking.rank(of: "nobody") == 0)
        #expect(ranking.leader?.id == "steady")
    }

    @Test func memberRankingBreaksFullTiesOnDisplayName() {
        let ranking = GroupMemberRanking([
            m("b", today: 2, total: 2, name: "Zoë"),
            m("a", today: 2, total: 2, name: "anna"),
        ], today: "2026-09-10")
        #expect(ranking.members.map(\.displayName) == ["anna", "Zoë"])
    }

    @Test func memberCountsDefaultToZeroForDocsFromBeforeTheCounters() throws {
        let old = Data(#"{"id":"u1","username":"tim","joinedAt":0}"#.utf8)
        let decoder = JSONDecoder()
        let member = try decoder.decode(GroupMember.self, from: old)
        #expect(member.displayName == "tim")
        #expect(member.todayCount == 0)
        #expect(member.totalCount == 0)
        #expect(member.countToday("2026-09-10") == 0)
    }

    @Test func noteTextIsTrimmedAndBounded() {
        #expect(GroupNote.sanitize("  er wordt lekker gejand  ") == "er wordt lekker gejand")
        #expect(GroupNote.sanitize("   ") == nil)
        #expect(GroupNote.sanitize("\n") == nil)
        #expect(GroupNote.sanitize(String(repeating: "x", count: 140)) != nil)
        #expect(GroupNote.sanitize(String(repeating: "x", count: 141)) == nil)
    }

    @Test func notesListNewestFirstAndKnowTheirAuthor() {
        let n = { (id: String, uid: String, seconds: TimeInterval) in
            GroupNote(id: id, uid: uid, displayName: uid, text: id, at: Date(timeIntervalSince1970: seconds))
        }
        let notes = [n("a", "u1", 100), n("c", "u2", 300), n("b", "u1", 200)]
        #expect(GroupNote.newestFirst(notes).map(\.id) == ["c", "b", "a"])
        // Same instant: a stable tiebreak, so the list never shuffles on reload.
        #expect(GroupNote.newestFirst([n("z", "u1", 100), n("y", "u1", 100)]).map(\.id) == ["y", "z"])
        #expect(n("a", "u1", 100).isMine("u1"))
        #expect(n("a", "u1", 100).isMine("u2") == false)
    }

    @Test func mateInviteSkipsMeAndExistingMates() {
        let members = [m("me", today: 0, total: 0), m("mate", today: 0, total: 0), m("stranger", today: 0, total: 0)]
        #expect(GroupMateInvite.targets(members, me: "me", mates: ["mate"]).map(\.id) == ["stranger"])
        // Alone, or already mates with everyone: nothing to send, so the button
        // that calls this can hide itself.
        #expect(GroupMateInvite.targets(members, me: "me", mates: ["mate", "stranger"]).isEmpty)
        #expect(GroupMateInvite.targets([m("me", today: 0, total: 0)], me: "me", mates: []).isEmpty)
    }

    @Test func mateInviteSummaryIsOneLine() {
        #expect(GroupMateInvite.summary(sent: 3, alreadyAsked: 0, failed: 0) == "3 requests sent.")
        #expect(GroupMateInvite.summary(sent: 1, alreadyAsked: 0, failed: 0) == "One request sent.")
        // A repeat tap is not an error: it reads as a receipt, not a failure.
        #expect(GroupMateInvite.summary(sent: 0, alreadyAsked: 2, failed: 0) == "2 were already waiting.")
        #expect(GroupMateInvite.summary(sent: 2, alreadyAsked: 1, failed: 1)
            == "2 requests sent. One was already waiting. One didn't go through — try again.")
        #expect(GroupMateInvite.summary(sent: 0, alreadyAsked: 0, failed: 0).contains("already mates"))
    }
}
