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
}
