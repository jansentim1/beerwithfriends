import BeerKit
import Foundation

// COMPILE-PARKED: no Xcode on this machine — written against the iOS 17 SDK +
// BeerKit protocol signatures, not yet compiled.

/// What a notification button asks for on a beer.
enum ReactionAction: Equatable, Sendable {
    case cheers
    case reply(ReplyKind)
}

/// Buffer between the notification-action callback and the signed-in services.
///
/// The AppDelegate learns about a tapped "Cheers 🍻" / "On my way 🏃" /
/// "Jealous 😩" button long before AppState has a `BeerServicing` (cold launch
/// from the lock screen: the action arrives while Firebase Auth is still
/// resolving). So actions are enqueued here and drained once AppState registers
/// a handler; a handler registered later immediately gets whatever piled up.
final class ReactionInbox: @unchecked Sendable {
    /// One queued notification action.
    struct Item: Equatable, Sendable {
        let beerId: String
        let action: ReactionAction
    }

    typealias Handler = @Sendable ([Item]) async -> Void

    /// One instance: the AppDelegate fills it, AppState drains it.
    static let shared = ReactionInbox()

    private let lock = NSLock()
    private var pending: [Item] = []
    private var handler: Handler?

    /// Queue one action (any thread — this runs from the notification callback).
    /// Drains straight away when a handler is already registered.
    func enqueue(_ item: Item) {
        lock.lock()
        pending.append(item)
        lock.unlock()
        drain()
    }

    /// Register (or clear, with nil) the writer. Registering drains the backlog.
    func setHandler(_ handler: Handler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
        drain()
    }

    /// Hands the whole backlog to the handler in one call. No-op without a
    /// handler: the items stay queued until one is registered.
    private func drain() {
        lock.lock()
        guard let handler, !pending.isEmpty else {
            lock.unlock()
            return
        }
        let items = pending
        pending = []
        lock.unlock()
        Task { await handler(items) }
    }
}
