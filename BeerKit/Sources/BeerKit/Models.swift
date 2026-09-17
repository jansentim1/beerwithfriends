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
    /// Who cheersed, by uid → the name to show. Server-maintained next to
    /// `cheersCount`, so the reactions sheet opens without another read.
    public var cheersBy: [String: String]
    /// Who quick-replied, by uid → the name to show. Mirrors `replies`.
    public var replyNames: [String: String]
    public init(id: String, ownerUid: String, ownerName: String, createdAt: Date,
                expiresAt: Date, hasPhoto: Bool, cheersCount: Int = 0, place: String? = nil,
                replies: [String: ReplyKind] = [:], drink: DrinkKind = .pils,
                placeCoordinate: Coordinate? = nil, cheersBy: [String: String] = [:],
                replyNames: [String: String] = [:]) {
        self.id = id; self.ownerUid = ownerUid; self.ownerName = ownerName
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.hasPhoto = hasPhoto; self.cheersCount = cheersCount; self.place = place
        self.replies = replies; self.drink = drink; self.placeCoordinate = placeCoordinate
        self.cheersBy = cheersBy; self.replyNames = replyNames
    }

    /// Has this drink run out for a viewer who first saw it at `seenAt`?
    /// Never seen (`nil`) means no: that is the whole point.
    public func hasFaded(seenAt: Date?, now: Date) -> Bool {
        if expiresAt <= now { return true }
        guard let seenAt else { return false }
        return now.timeIntervalSince(seenAt) >= Self.seenLifetime
    }

    /// The reactions sheet's content: everyone who cheersed, then everyone who
    /// quick-replied, each sorted by name (the doc mirrors carry no order, and
    /// a drink lives an hour — recency adds nothing worth a read).
    public var reactions: Reactions {
        Reactions(
            cheers: cheersBy.map { Reactor(id: $0.key, name: $0.value, reply: nil) }
                .sorted { $0.sortKey < $1.sortKey },
            replies: replies.map { Reactor(id: $0.key, name: replyNames[$0.key] ?? "a mate", reply: $0.value) }
                .sorted { $0.sortKey < $1.sortKey }
        )
    }
    /// How long a glass takes to empty (Tim: "beers are empty in 15 minutes").
    /// The row itself stays in the feed until `expiresAt` (1 h), glass empty.
    public static let drinkDuration: TimeInterval = 15 * 60
    /// Two clocks, because a drink nobody saw is not the same as a drink
    /// everybody saw (Tim, 2026-09-17: "if you have seen them they go away in
    /// two hours but ones you have never seen don't go away").
    ///
    /// `seenLifetime` is the one you feel: two hours after a drink first shows
    /// up in YOUR feed it leaves YOUR feed. Until then it stays, however long
    /// that takes — which is what makes it worth opening the app.
    public static let seenLifetime: TimeInterval = 2 * 3600
    /// The hard cap the server enforces, so nothing is ephemeral in name only:
    /// every drink and its photo are deleted a day after logging, seen or not.
    public static let lifetime: TimeInterval = 24 * 3600
    /// 1.0 when just poured, 0.0 fifteen minutes later.
    public func fillLevel(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(createdAt)
        return min(1, max(0, 1 - elapsed / Self.drinkDuration))
    }
    public func replyCount(_ kind: ReplyKind) -> Int { replies.values.filter { $0 == kind }.count }
    public static let placeMaxLength = 60
    public static func expiry(from createdAt: Date) -> Date { createdAt.addingTimeInterval(lifetime) }

    /// What the feed and the map show: one drink per person, the newest, and
    /// only while it is still live for this viewer (Tim: "only one update per
    /// person should stay in the main overview, so it overwrites"). Newest
    /// first. The server deletes superseded drinks too; this keeps the screens
    /// right before it has.
    public static func latestPerOwner(_ logs: [BeerLog], now: Date,
                                      seenAt: [String: Date] = [:]) -> [BeerLog] {
        var newest: [String: BeerLog] = [:]
        for log in logs where !log.hasFaded(seenAt: seenAt[log.id], now: now) {
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
    // Beers first, in the order you'd meet them at a bar: the small one, the
    // big one, the interesting one, the dark one. Gijs, 2026-09-17: "je kan
    // pils, speciaal bier, maar geen pint, of stout".
    case pils, pint, stein, special, stout, wine, bubbles, cocktail, whisky

    public var label: String {
        switch self {
        case .pils: return "Pils"
        case .pint: return "Pint"
        case .stein: return "Stein"
        case .special: return "Special beer"
        case .stout: return "Stout"
        case .wine: return "Wine"
        case .bubbles: return "Bubbles"
        case .cocktail: return "Cocktail"
        case .whisky: return "Whisky"
        }
    }
    public var emoji: String {
        switch self {
        case .pils: return "🍺"
        case .pint: return "🍺"
        case .stein: return "🍻"
        case .special: return "🍻"
        case .stout: return "🍺"
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
        case .pint: return "a pint"
        case .stein: return "a stein"
        case .special: return "a special beer"
        case .stout: return "a stout"
        case .wine: return "a glass of wine"
        case .bubbles: return "bubbles"
        case .cocktail: return "a cocktail"
        case .whisky: return "a whisky"
        }
    }
}

/// One mate in the reactions sheet: who they are, what they left.
public struct Reactor: Equatable, Identifiable, Sendable {
    public var id: String          // uid
    public var name: String
    /// nil for a cheers, the kind for a quick reply.
    public var reply: ReplyKind?
    public init(id: String, name: String, reply: ReplyKind?) {
        self.id = id; self.name = name; self.reply = reply
    }
    /// Case-insensitive name, then uid so the order never wobbles between reads.
    var sortKey: String { name.lowercased() + "\u{0}" + id }
}

/// What a drink's row has collected: cheers first, quick replies after.
public struct Reactions: Equatable, Sendable {
    public var cheers: [Reactor]
    public var replies: [Reactor]
    public init(cheers: [Reactor], replies: [Reactor]) {
        self.cheers = cheers; self.replies = replies
    }
    public var isEmpty: Bool { cheers.isEmpty && replies.isEmpty }
    /// The count the sheet shows: the names it can actually list, which can lag
    /// `cheersCount` by one function run.
    public var cheersCount: Int { cheers.count }
}
