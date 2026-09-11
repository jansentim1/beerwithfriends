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
    /// What is in the glass. Old docs without the field decode as `.pils`.
    public var drink: DrinkKind
    /// The bar's or city's coordinate (never the device fix); only with `place`.
    public var placeCoordinate: Coordinate?
    public init(id: String, ownerUid: String, ownerName: String, createdAt: Date,
                expiresAt: Date, hasPhoto: Bool, cheersCount: Int = 0, place: String? = nil,
                replies: [String: ReplyKind] = [:], drink: DrinkKind = .pils,
                placeCoordinate: Coordinate? = nil) {
        self.id = id; self.ownerUid = ownerUid; self.ownerName = ownerName
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.hasPhoto = hasPhoto; self.cheersCount = cheersCount; self.place = place
        self.replies = replies; self.drink = drink; self.placeCoordinate = placeCoordinate
    }
    /// How long a glass takes to empty (Tim: "beers are empty in 15 minutes").
    /// The row itself stays in the feed until `expiresAt` (2 h), glass empty.
    public static let drinkDuration: TimeInterval = 15 * 60
    /// How long a drink stays in the feed and on the map (Tim, 2026-09-11:
    /// "2 hours max"). The server clamps anything longer and the hourly
    /// cleanup deletes what has expired.
    public static let lifetime: TimeInterval = 2 * 3600
    /// 1.0 when just poured, 0.0 fifteen minutes later.
    public func fillLevel(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(createdAt)
        return min(1, max(0, 1 - elapsed / Self.drinkDuration))
    }
    public func replyCount(_ kind: ReplyKind) -> Int { replies.values.filter { $0 == kind }.count }
    public static let placeMaxLength = 60
    public static func expiry(from createdAt: Date) -> Date { createdAt.addingTimeInterval(lifetime) }

    /// What the feed and the map show: one drink per person, the newest, and
    /// only while it is alive (Tim: "only one update per person should stay in
    /// the main overview, so it overwrites"). Newest first. The server deletes
    /// superseded drinks too; this keeps the screens right before it has.
    public static func latestPerOwner(_ logs: [BeerLog], now: Date) -> [BeerLog] {
        var newest: [String: BeerLog] = [:]
        for log in logs where log.expiresAt > now {
            if let current = newest[log.ownerUid], current.createdAt >= log.createdAt { continue }
            newest[log.ownerUid] = log
        }
        return newest.values.sorted { $0.createdAt > $1.createdAt }
    }
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

/// Latitude/longitude rounded to ~100 m; a place's coordinate, never a person's.
public struct Coordinate: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) {
        self.latitude = (latitude * 1000).rounded() / 1000
        self.longitude = (longitude * 1000).rounded() / 1000
    }
}

/// What is in the glass. Raw values are the wire format (rules-pinned).
public enum DrinkKind: String, Codable, CaseIterable, Sendable {
    case pils, special, wine, bubbles, cocktail, whisky

    public var label: String {
        switch self {
        case .pils: return "Pils"
        case .special: return "Special beer"
        case .wine: return "Wine"
        case .bubbles: return "Bubbles"
        case .cocktail: return "Cocktail"
        case .whisky: return "Whisky"
        }
    }
    public var emoji: String {
        switch self {
        case .pils: return "🍺"
        case .special: return "🍻"
        case .wine: return "🍷"
        case .bubbles: return "🥂"
        case .cocktail: return "🍸"
        case .whisky: return "🥃"
        }
    }
    /// "Tim is having a pils 🍺" / "Tim is having a glass of wine 🍷"
    public var pushPhrase: String {
        switch self {
        case .pils: return "a pils"
        case .special: return "a special beer"
        case .wine: return "a glass of wine"
        case .bubbles: return "bubbles"
        case .cocktail: return "a cocktail"
        case .whisky: return "a whisky"
        }
    }
}
