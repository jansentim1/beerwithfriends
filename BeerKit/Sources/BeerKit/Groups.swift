import Foundation
#if canImport(Combine)
import Combine
#endif

/// A group of mates whose drinks are counted together, for the leaderboard.
public struct GroupSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Join code; only present for groups the user is in.
    public var code: String?
    public var memberCount: Int
    /// Server-maintained: `todayDate` is "YYYY-MM-DD" in Europe/Amsterdam.
    public var todayDate: String
    public var todayCount: Int
    public var totalCount: Int
    public var isMine: Bool

    public init(id: String, name: String, code: String? = nil, memberCount: Int,
                todayDate: String, todayCount: Int, totalCount: Int, isMine: Bool) {
        self.id = id; self.name = name; self.code = code; self.memberCount = memberCount
        self.todayDate = todayDate; self.todayCount = todayCount; self.totalCount = totalCount
        self.isMine = isMine
    }

    /// The count that belongs to `today`; stale groups show 0 without a server write.
    public func countToday(_ today: String) -> Int { todayDate == today ? todayCount : 0 }

    public static let nameMaxLength = 30
}

public struct GroupMember: Codable, Equatable, Identifiable, Sendable {
    public var id: String          // uid
    public var username: String
    public var joinedAt: Date
    public init(id: String, username: String, joinedAt: Date) {
        self.id = id; self.username = username; self.joinedAt = joinedAt
    }
}

public enum GroupError: Error, Equatable { case notFound, full, alreadyMember, invalidName, notMember }

public protocol GroupServicing: Sendable {
    /// Every group, live, sorted by the caller later. Includes `isMine`.
    func observeGroups() -> AsyncThrowingStream<[GroupSummary], Error>
    func members(of groupId: String) async throws -> [GroupMember]
    func create(name: String) async throws -> GroupSummary
    func join(code: String) async throws -> GroupSummary
    func leave(groupId: String) async throws
}

public enum GroupDay {
    /// "YYYY-MM-DD" in Europe/Amsterdam, the day the server counts in.
    public static func today(now: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now)
    }
}

@MainActor
public final class LeaderboardViewModel: ObservableObject {
    @Published public private(set) var groups: [GroupSummary] = []
    @Published public var errorMessage: String?

    private let service: any GroupServicing
    private let now: () -> Date
    private var observation: Task<Void, Never>?

    public init(service: any GroupServicing, now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    /// Mine first, then by today's count, then total, then name.
    public var ranked: [GroupSummary] {
        let today = GroupDay.today(now: now())
        return groups.sorted {
            let a = ($0.countToday(today), $0.totalCount), b = ($1.countToday(today), $1.totalCount)
            if a != b { return a > b }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    public var mine: [GroupSummary] { ranked.filter(\.isMine) }
    public var others: [GroupSummary] { ranked.filter { !$0.isMine } }
    /// 1-based rank in the overall leaderboard.
    public func rank(of group: GroupSummary) -> Int { (ranked.firstIndex(where: { $0.id == group.id }) ?? 0) + 1 }

    public func start() async {
        if let previous = observation { previous.cancel(); await previous.value }
        let task = Task { [service] in
            do {
                for try await list in service.observeGroups() { self.groups = list }
            } catch {
                if !Task.isCancelled { self.errorMessage = "Couldn't load the leaderboard." }
            }
        }
        observation = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    public func create(name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...GroupSummary.nameMaxLength).contains(trimmed.count) else {
            errorMessage = "Group names are 1–\(GroupSummary.nameMaxLength) characters."
            return false
        }
        do { _ = try await service.create(name: trimmed); return true }
        catch { errorMessage = "Couldn't create the group — try again."; return false }
    }

    public func join(code: String) async -> Bool {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        do { _ = try await service.join(code: normalized); return true }
        catch GroupError.notFound { errorMessage = "No group with code \(normalized)." }
        catch GroupError.full { errorMessage = "That group is full." }
        catch GroupError.alreadyMember { errorMessage = "You're already in that group." }
        catch { errorMessage = "Couldn't join — try again." }
        return false
    }

    public func leave(_ group: GroupSummary) async {
        do { try await service.leave(groupId: group.id) }
        catch { errorMessage = "Couldn't leave the group — try again." }
    }
}
