import Foundation

public enum Timeout {
    /// Runs `operation`, giving up after `seconds`. Returns nil on timeout. The
    /// operation keeps running detached if it ignores cancellation (Firestore's
    /// async wrappers do), which is exactly why callers must not block on it.
    public static func run<T: Sendable>(
        seconds: Double,
        _ operation: @escaping @Sendable () async -> T
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
