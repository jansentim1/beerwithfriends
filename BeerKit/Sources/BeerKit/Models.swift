import Foundation

public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String            // Firebase uid
    public var username: String      // normalized lowercase
    public var displayName: String
    public var beerCount: Int
    public var createdAt: Date
    public init(id: String, username: String, displayName: String, beerCount: Int = 0, createdAt: Date) {
        self.id = id; self.username = username; self.displayName = displayName
        self.beerCount = beerCount; self.createdAt = createdAt
    }
}

public struct BeerLog: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var ownerUid: String
    public var ownerName: String
    public var createdAt: Date
    public var expiresAt: Date
    public var hasPhoto: Bool
    public var cheersCount: Int
    /// Optional, opt-in: the bar or city the beer was logged at (never coordinates).
    public var place: String?
    /// Quick replies by uid, maintained server-side from `beers/{id}/replies/{uid}`.
    public var replies: [String: ReplyKind]
    public init(id: String, ownerUid: String, ownerName: String, createdAt: Date,
                expiresAt: Date, hasPhoto: Bool, cheersCount: Int = 0, place: String? = nil,
                replies: [String: ReplyKind] = [:]) {
        self.id = id; self.ownerUid = ownerUid; self.ownerName = ownerName
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.hasPhoto = hasPhoto; self.cheersCount = cheersCount; self.place = place
        self.replies = replies
    }
    public func replyCount(_ kind: ReplyKind) -> Int { replies.values.filter { $0 == kind }.count }
    public static let placeMaxLength = 60
    public static func expiry(from createdAt: Date) -> Date { createdAt.addingTimeInterval(24 * 3600) }
}

public struct FriendRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String            // sender uid
    public var fromUsername: String
    public var fromDisplayName: String
    public var sentAt: Date
    public init(id: String, fromUsername: String, fromDisplayName: String, sentAt: Date) {
        self.id = id; self.fromUsername = fromUsername
        self.fromDisplayName = fromDisplayName; self.sentAt = sentAt
    }
}

/// One-tap reactions to a mate's beer besides cheers. Raw values are the wire format
/// (Firestore `kind`, rules-pinned) and the notification action identifiers.
public enum ReplyKind: String, Codable, CaseIterable, Sendable {
    case onMyWay = "onmyway"
    case jealous = "jealous"

    public var label: String {
        switch self {
        case .onMyWay: return "On my way"
        case .jealous: return "Jealous"
        }
    }
    public var emoji: String {
        switch self {
        case .onMyWay: return "🏃"
        case .jealous: return "😩"
        }
    }
}
