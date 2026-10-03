import Foundation
#if canImport(Combine)
import Combine
#endif

/// A group of mates whose drinks are counted together, for the leaderboard.
public struct GroupSummary: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    /// Join code. Present for every group, because the rules let any signed-in
    /// user read `groups/{id}`; what is gated is where it is SHOWN (the invite
    /// section, members only) and it is what the one-tap Join sends.
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
    public var displayName: String
    public var joinedAt: Date
    /// Server-maintained (countDrinkForGroups), with the group's Europe/Amsterdam
    /// rollover: this person's own drinks, for the ranking inside the group.
    public var todayDate: String
    public var todayCount: Int
    public var totalCount: Int

    public init(id: String, username: String, displayName: String? = nil, joinedAt: Date,
                todayDate: String = "", todayCount: Int = 0, totalCount: Int = 0) {
        self.id = id; self.username = username; self.displayName = displayName ?? username; self.joinedAt = joinedAt
        self.todayDate = todayDate; self.todayCount = todayCount; self.totalCount = totalCount
    }

    /// The count that belongs to `today`; a member who last drank on another day
    /// shows 0 without waiting for a server write, exactly like GroupSummary.
    public func countToday(_ today: String) -> Int { todayDate == today ? todayCount : 0 }

    private enum CodingKeys: String, CodingKey { case id, username, displayName, joinedAt, todayDate, todayCount, totalCount }

    /// Hand-written so member docs from before the counters existed still decode:
    /// synthesized Codable ignores property defaults and would throw on the
    /// missing keys.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? username
        joinedAt = try c.decode(Date.self, forKey: .joinedAt)
        todayDate = try c.decodeIfPresent(String.self, forKey: .todayDate) ?? ""
        todayCount = try c.decodeIfPresent(Int.self, forKey: .todayCount) ?? 0
        totalCount = try c.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
    }
}

/// The ranking of PEOPLE inside one group. Built once from a members list, then
/// asked for positions, so a row does not re-sort per cell.
///
/// Same order as `LeaderboardViewModel.ranked` for groups — today's count, then
/// total, then name — so the two leaderboards feel like one idea. Ties break on
/// the name, which means every rank is distinct (no shared 2nd place).
public struct GroupMemberRanking: Equatable, Sendable {
    /// Best first.
    public let members: [GroupMember]
    private let positions: [String: Int]

    public init(_ members: [GroupMember], today: String = GroupDay.today()) {
        let sorted = members.sorted {
            let a = ($0.countToday(today), $0.totalCount), b = ($1.countToday(today), $1.totalCount)
            if a != b { return a > b }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        self.members = sorted
        self.positions = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0 + 1) })
    }

    /// 1-based rank, matching `LeaderboardViewModel.rank(of:)`; 0 for a member
    /// that is not in this ranking.
    public func rank(of memberId: String) -> Int { positions[memberId] ?? 0 }
    public var leader: GroupMember? { members.first }
}

/// A line a member posted to their group: "wilde even meedelen dat er lekker
/// wordt gejand op deze zaterdagmiddag". Created once, never edited.
public struct GroupNote: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var uid: String
    public var displayName: String
    public var text: String
    public var at: Date

    public init(id: String, uid: String, displayName: String, text: String, at: Date) {
        self.id = id; self.uid = uid; self.displayName = displayName; self.text = text; self.at = at
    }

    public static let textMaxLength = 140
    /// Server-enforced (enforceNoteCooldown): a second note inside this window is
    /// deleted and nobody is pushed, so the composer should say so up front.
    public static let cooldown: TimeInterval = 60

    /// The trimmed text the rules will accept, or nil when it is empty or too
    /// long — the one check the composer needs before sending.
    public static func sanitize(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...textMaxLength).contains(trimmed.count) ? trimmed : nil
    }

    /// What the list shows: newest first, ties by id so the order is stable.
    public static func newestFirst(_ notes: [GroupNote]) -> [GroupNote] {
        notes.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at > $1.at }
    }

    public func isMine(_ uid: String) -> Bool { self.uid == uid }
}

/// One tap, every member: the mate requests a group lets you send in bulk
/// (Menno: "in een click al je maten kan delen met anderen"). Pure, so the
/// counting and the one line the user reads are both testable.
public enum GroupMateInvite {
    /// Who a tap asks: everyone in the group except me and the people I'm
    /// already mates with. Order is the caller's (the ranking), so the summary
    /// counts the same people the list shows.
    public static func targets(_ members: [GroupMember], me: String, mates: Set<String>) -> [GroupMember] {
        members.filter { $0.id != me && !mates.contains($0.id) }
    }

    /// One line for the whole batch, never one alert per person.
    /// `alreadyAsked` is not a failure: a second tap, or a request the other
    /// side hasn't accepted yet, lands there (`FriendRequestError.alreadyAsked`).
    public static func summary(sent: Int, alreadyAsked: Int, failed: Int) -> String {
        var parts: [String] = []
        if sent > 0 { parts.append(sent == 1 ? "One request sent." : "\(sent) requests sent.") }
        if alreadyAsked > 0 {
            parts.append(alreadyAsked == 1 ? "One was already waiting." : "\(alreadyAsked) were already waiting.")
        }
        if failed > 0 {
            parts.append(failed == 1 ? "One didn't go through — try again." : "\(failed) didn't go through — try again.")
        }
        if parts.isEmpty { return "Nobody new here — you're already mates with the whole group. 🍻" }
        return parts.joined(separator: " ")
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
    /// The group's notes, newest first. Members only by rule, so this is asked
    /// for a group I'm in and nothing else.
    func notes(of groupId: String) async throws -> [GroupNote]
    /// Writes one note as the signed-in member. `text` has already been through
    /// `GroupNote.sanitize`; `displayName` rides along because the rules demand
    /// it on the doc and a reader must not need a fetch per line to show it.
    func postNote(groupId: String, text: String, displayName: String) async throws
    /// The author taking their own words back.
    func deleteNote(groupId: String, noteId: String) async throws
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
