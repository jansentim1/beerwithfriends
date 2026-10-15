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
    /// 2026-09-10 at `hh:mm` UTC, for "first out" stamps.
    func at(_ hh: Int, _ mm: Int = 0) -> Date { Date(timeIntervalSince1970: 1_788_998_400 + Double(hh * 3600 + mm * 60)) }
    func g(_ id: String, out: Int, firstAt: Date? = nil, today: Int = 0, total: Int = 0,
           date: String = "2026-09-10", mine: Bool = false) -> GroupSummary {
        GroupSummary(id: id, name: id, memberCount: 3, todayDate: date, todayCount: today, totalCount: total,
                     todayOutCount: out, todayFirstAt: firstAt, isMine: mine)
    }

    @Test func todayIsAmsterdamDate() {
        #expect(GroupDay.today(now: now()) == "2026-09-10")
        // 23:30 UTC on the 10th is already the 11th in Amsterdam (CEST).
        #expect(GroupDay.today(now: Date(timeIntervalSince1970: 1_789_083_000)) == "2026-09-11")
    }

    @Test func anchorDateIsTheTenthInAmsterdam() {
        #expect(GroupDay.today(now: at(0)) == "2026-09-10")
        #expect(GroupDay.clock(at(17, 12)) == "19:12")   // CEST
    }

    @Test @MainActor func rankingUsesWhoIsOutNotHowMuch() async {
        let svc = FakeGroups()
        let vm = LeaderboardViewModel(service: svc, now: now)
        let running = Task { await vm.start() }
        while svc.continuation == nil { await Task.yield() }
        svc.continuation?.yield([
            g("quiet", out: 5, firstAt: at(9), today: 30, total: 90, date: "2026-09-09"), // stale: nobody out today
            g("late", out: 2, firstAt: at(20), today: 12, total: 10),  // drank the most: irrelevant
            g("early", out: 2, firstAt: at(17), today: 2, total: 40, mine: true),
            g("crowd", out: 3, firstAt: at(21), today: 3),
            g("new", out: 0),
        ])
        for _ in 0..<50 where vm.groups.isEmpty { await Task.yield() }
        #expect(vm.ranked.map(\.id) == ["crowd", "early", "late", "new", "quiet"])
        #expect(vm.rank(of: vm.groups.first { $0.id == "early" }!) == 2)
        #expect(vm.mine.map(\.id) == ["early"])
        running.cancel(); await running.value
    }

    @Test func groupOutTodayIgnoresAStaleDay() {
        let stale = g("x", out: 4, firstAt: at(18), date: "2026-09-09")
        #expect(stale.outToday("2026-09-10") == 0)
        #expect(stale.firstOutAt("2026-09-10") == nil)
        let live = g("y", out: 4, firstAt: at(18))
        #expect(live.outToday("2026-09-10") == 4)
        #expect(live.firstOutAt("2026-09-10") == at(18))
    }

    @Test func groupSummaryDecodesDocsFromBeforeWhoIsOut() throws {
        let old = Data(#"{"id":"g","name":"De Kroeg","memberCount":3,"todayDate":"2026-09-10","todayCount":4,"totalCount":9,"isMine":true}"#.utf8)
        let group = try JSONDecoder().decode(GroupSummary.self, from: old)
        #expect(group.todayOutCount == 0)
        #expect(group.todayFirstAt == nil)
        #expect(group.outToday("2026-09-10") == 0)
        #expect(group.todayCount == 4)
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

    func m(_ id: String, today: Int, total: Int, date: String = "2026-09-10", name: String? = nil,
           firstAt: Date? = nil) -> GroupMember {
        GroupMember(id: id, username: id, displayName: name ?? id, joinedAt: Date(timeIntervalSince1970: 0),
                    todayDate: date, todayCount: today, totalCount: total, todayFirstAt: firstAt)
    }

    @Test func memberRankingPutsFirstOutFirstNotMostDrinks() {
        let ranking = GroupMemberRanking([
            m("quiet", today: 9, total: 90, date: "2026-09-09", firstAt: at(8)),  // stale: not out today
            m("heavy", today: 12, total: 10, firstAt: at(20)),                    // most drinks, out last
            m("early", today: 1, total: 40, firstAt: at(17, 12)),
            m("zed", today: 0, total: 0, name: "Zed"),
            m("anna", today: 0, total: 50, name: "anna"),
        ], today: "2026-09-10")
        #expect(ranking.members.map(\.id) == ["early", "heavy", "anna", "quiet", "zed"])
        #expect(ranking.rank(of: "early") == 1)
        #expect(ranking.rank(of: "heavy") == 2)
        #expect(ranking.rank(of: "nobody") == 0)
        #expect(ranking.leader?.id == "early")
    }

    @Test func memberRankingBreaksSameMinuteTiesOnDisplayName() {
        let ranking = GroupMemberRanking([
            m("b", today: 2, total: 2, name: "Zoë", firstAt: at(18)),
            m("a", today: 1, total: 2, name: "anna", firstAt: at(18)),
        ], today: "2026-09-10")
        #expect(ranking.members.map(\.displayName) == ["anna", "Zoë"])
        #expect(Set([ranking.rank(of: "a"), ranking.rank(of: "b")]) == [1, 2])   // still distinct
    }

    @Test func memberOutTodayOnlyCountsTheCurrentDay() {
        #expect(m("a", today: 1, total: 1, firstAt: at(18)).outToday("2026-09-10") == at(18))
        #expect(m("a", today: 1, total: 1, date: "2026-09-09", firstAt: at(18)).outToday("2026-09-10") == nil)
        // Joined today, nothing logged yet: todayDate is today but they are not out.
        #expect(m("a", today: 0, total: 0).outToday("2026-09-10") == nil)
        // Logged today before the stamp existed: out, time unknown, still sorted as out.
        #expect(m("a", today: 2, total: 2).outToday("2026-09-10") == .distantPast)
    }

    @Test func memberCountsDefaultToZeroForDocsFromBeforeTheCounters() throws {
        let old = Data(#"{"id":"u1","username":"tim","joinedAt":0}"#.utf8)
        let decoder = JSONDecoder()
        let member = try decoder.decode(GroupMember.self, from: old)
        #expect(member.displayName == "tim")
        #expect(member.todayCount == 0)
        #expect(member.totalCount == 0)
        #expect(member.countToday("2026-09-10") == 0)
        #expect(member.todayFirstAt == nil)
        #expect(member.outToday("2026-09-10") == nil)
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
