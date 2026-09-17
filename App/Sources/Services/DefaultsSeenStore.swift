import BeerKit
import Foundation

/// `SeenStoring` on `UserDefaults`: a reading position, not shared state, so it
/// lives on the device and nothing about it reaches the server. A reinstall
/// forgets it and a drink shows up once more, which is the harmless direction
/// for this to fail in.
final class DefaultsSeenStore: SeenStoring, @unchecked Sendable {
    private let key = "seenDrinkAt"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private func load() -> [String: Date] {
        (defaults.dictionary(forKey: key) as? [String: Date]) ?? [:]
    }

    func seenAt(ids: [String]) -> [String: Date] {
        lock.lock(); defer { lock.unlock() }
        let wanted = Set(ids)
        return load().filter { wanted.contains($0.key) }
    }

    func markSeen(ids: [String], at: Date) {
        lock.lock(); defer { lock.unlock() }
        var times = load()
        var changed = false
        for id in ids where times[id] == nil {
            times[id] = at
            changed = true
        }
        // Writing on every tick would churn the defaults plist for nothing.
        if changed { defaults.set(times, forKey: key) }
    }

    func forget(idsNotIn keep: Set<String>) {
        lock.lock(); defer { lock.unlock() }
        let times = load()
        let kept = times.filter { keep.contains($0.key) }
        if kept.count != times.count { defaults.set(kept, forKey: key) }
    }
}
