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
    public init(id: String, ownerUid: String, ownerName: String, createdAt: Date,
                expiresAt: Date, hasPhoto: Bool, cheersCount: Int = 0) {
        self.id = id; self.ownerUid = ownerUid; self.ownerName = ownerName
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.hasPhoto = hasPhoto; self.cheersCount = cheersCount
    }
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
