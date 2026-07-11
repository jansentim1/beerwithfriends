import Foundation

public enum PhotoChipState: Equatable, Sendable { case none, sealed, seen, expired }

public extension BeerLog {
    func photoChipState(viewedByMe: Bool, now: Date) -> PhotoChipState {
        guard hasPhoto else { return .none }
        if now >= expiresAt { return .expired }
        return viewedByMe ? .seen : .sealed
    }
}
