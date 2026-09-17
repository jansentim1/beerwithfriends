import Foundation

/// When each drink first showed up in this person's feed. A drink fades from
/// their feed two hours after that moment, and never before it (Tim,
/// 2026-09-17), so this is the clock the feed is actually read against.
///
/// Per viewer and per device on purpose: it is a reading position, not shared
/// state, and a wrong guess costs a drink staying one round longer.
public protocol SeenStoring: Sendable {
    /// First-seen time per beer id, for the ids asked about.
    func seenAt(ids: [String]) -> [String: Date]
    /// Records `at` as the first-seen time for ids that have none. Ids already
    /// recorded keep their original time — seeing a row again must not restart
    /// the two hours.
    func markSeen(ids: [String], at: Date)
    /// Drops ids that are gone, so the store cannot grow without bound.
    func forget(idsNotIn: Set<String>)
}

/// In-memory, for tests and previews.
public final class InMemorySeenStore: SeenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var times: [String: Date] = [:]
    public init(_ initial: [String: Date] = [:]) { times = initial }

    public func seenAt(ids: [String]) -> [String: Date] {
        lock.lock(); defer { lock.unlock() }
        return times.filter { ids.contains($0.key) }
    }
    public func markSeen(ids: [String], at: Date) {
        lock.lock(); defer { lock.unlock() }
        for id in ids where times[id] == nil { times[id] = at }
    }
    public func forget(idsNotIn keep: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        times = times.filter { keep.contains($0.key) }
    }
    /// Test hook: everything recorded so far.
    public var all: [String: Date] {
        lock.lock(); defer { lock.unlock() }
        return times
    }
}
