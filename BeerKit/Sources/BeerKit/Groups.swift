import Foundation
#if canImport(Combine)
import Combine
#endif

/// A group of mates who go out together. Ranked by how many of them are OUT
/// today, never by how much anyone drank (App Store guideline 1.4.3).
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
    /// Server-maintained: distinct members with a drink on `todayDate`, and when
    /// the first of them logged (the one who opened the round). Absent on docs
    /// from before 2026-10-15, which read as 0 / nil.
    public var todayOutCount: Int
    public var todayFirstAt: Date?
    public var isMine: Bool

    public init(id: String, name: String, code: String? = nil, memberCount: Int,
                todayDate: String, todayCount: Int, totalCount: Int,
                todayOutCount: Int = 0, todayFirstAt: Date? = nil, isMine: Bool) {
        self.id = id; self.name = name; self.code = code; self.memberCount = memberCount
        self.todayDate = todayDate; self.todayCount = todayCount; self.totalCount = totalCount
        self.todayOutCount = todayOutCount; self.todayFirstAt = todayFirstAt
        self.isMine = isMine
    }

    /// The count that belongs to `today`; stale groups show 0 without a server write.
    public func countToday(_ today: String) -> Int { todayDate == today ? todayCount : 0 }

    /// How many members are out `today`; a stale group shows 0, like `countToday`.
    public func outToday(_ today: String) -> Int { todayDate == today ? todayOutCount : 0 }

    /// When the first member went out `today`; nil for a stale group.
    public func firstOutAt(_ today: String) -> Date? { todayDate == today ? todayFirstAt : nil }

    private enum CodingKeys: String, CodingKey {
        case id, name, code, memberCount, todayDate, todayCount, totalCount, todayOutCount, todayFirstAt, isMine
    }

    /// Hand-written for the same reason as GroupMember's: group docs from before
    /// the "who's out" fields must still decode.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        code = try c.decodeIfPresent(String.self, forKey: .code)
        memberCount = try c.decodeIfPresent(Int.self, forKey: .memberCount) ?? 0
        todayDate = try c.decodeIfPresent(String.self, forKey: .todayDate) ?? ""
        todayCount = try c.decodeIfPresent(Int.self, forKey: .todayCount) ?? 0
        totalCount = try c.decodeIfPresent(Int.self, forKey: .totalCount) ?? 0
        todayOutCount = try c.decodeIfPresent(Int.self, forKey: .todayOutCount) ?? 0
        todayFirstAt = try c.decodeIfPresent(Date.self, forKey: .todayFirstAt)
        isMine = try c.decodeIfPresent(Bool.self, forKey: .isMine) ?? false
    }

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
    /// Server-maintained: this person's first drink on `todayDate`, i.e. when
    /// they went out. nil on docs from before 2026-10-15.
    public var todayFirstAt: Date?

    public init(id: String, username: String, displayName: String? = nil, joinedAt: Date,
                todayDate: String = "", todayCount: Int = 0, totalCount: Int = 0, todayFirstAt: Date? = nil) {
        self.id = id; self.username = username; self.displayName = displayName ?? username; self.joinedAt = joinedAt
        self.todayDate = todayDate; self.todayCount = todayCount; self.totalCount = totalCount
        self.todayFirstAt = todayFirstAt
    }

    /// The count that belongs to `today`; a member who last drank on another day
    /// shows 0 without waiting for a server write, exactly like GroupSummary.
    public func countToday(_ today: String) -> Int { todayDate == today ? todayCount : 0 }

    /// When this person went out `today`, or nil when they haven't (a stale day
    /// reads as not out, without waiting for a server write). A doc that has a
    /// count today but no stamp (written before the field existed) is out, at an
    /// unknown time: it falls back to `distantPast` so it still sorts as out.
    public func outToday(_ today: String) -> Date? {
        guard todayDate == today, todayCount > 0 || todayFirstAt != nil else { return nil }
        return todayFirstAt ?? .distantPast
    }

    private enum CodingKeys: String, CodingKey { case id, username, displayName, joinedAt, todayDate, todayCount, totalCount, todayFirstAt }

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
        todayFirstAt = try c.decodeIfPresent(Date.self, forKey: .todayFirstAt)
    }
}

/// The ranking of PEOPLE inside one group. Built once from a members list, then
/// asked for positions, so a row does not re-sort per cell.
///
/// "Who's out", never how much: members out today come first, in the order they
/// went out (first one out is #1, the crown); everyone else follows by name.
/// Ties (same minute, or nobody out) break on the name, which means every rank
/// is distinct (no shared 2nd place). Same idea as `LeaderboardViewModel.ranked`
/// for groups, one scale down.
public struct GroupMemberRanking: Equatable, Sendable {
    /// First one out first.
    public let members: [GroupMember]
    private let positions: [String: Int]

    public init(_ members: [GroupMember], today: String = GroupDay.today()) {
        let sorted = members.sorted {
            switch ($0.outToday(today), $1.outToday(today)) {
            case let (a?, b?) where a != b: return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: break
            }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        self.members = sorted
        self.positions = Dictionary(uniqueKeysWithValues: sorted.enumerated().map { ($1.id, $0 + 1) })
    }

    /// 1-based rank, matching `LeaderboardViewModel.rank(of:)`; 0 for a member
    /// that is not in this ranking.
    public func rank(of memberId: String) -> Int { positions[memberId] ?? 0 }
    /// Rank 1. Out today only if `outToday` says so: on a quiet day it is just
    /// the first name alphabetically.
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

    /// "19:12": the 24-hour clock in Europe/Amsterdam, the zone the day is
    /// counted in, for "Out since 19:12".
    public static func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
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

    /// Most members out today first, then the group whose first member went out
    /// earliest, then name. Never by how much anyone drank (guideline 1.4.3).
    /// A group with people out but no stamp (a doc from before the field) sorts
    /// after the stamped ones at the same head count.
    public var ranked: [GroupSummary] {
        let today = GroupDay.today(now: now())
        return groups.sorted {
            let a = $0.outToday(today), b = $1.outToday(today)
            if a != b { return a > b }
            let fa = $0.firstOutAt(today) ?? .distantFuture, fb = $1.firstOutAt(today) ?? .distantFuture
            if fa != fb { return fa < fb }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    public var mine: [GroupSummary] { ranked.filter(\.isMine) }
    public var others: [GroupSummary] { ranked.filter { !$0.isMine } }
    /// 1-based rank in tonight's round across all groups.
    public func rank(of group: GroupSummary) -> Int { (ranked.firstIndex(where: { $0.id == group.id }) ?? 0) + 1 }

    public func start() async {
        if let previous = observation { previous.cancel(); await previous.value }
        let task = Task { [service] in
            do {
                for try await list in service.observeGroups() { self.groups = list }
            } catch {
                if !Task.isCancelled { self.errorMessage = "Couldn't load the groups." }
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
