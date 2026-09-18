import Foundation

/// What a mate can send back on your drink, beyond a cheers: one of the preset
/// emoji, any other emoji, or a few words of their own (Tim, 2026-09-18: "i
/// also want more emojis you can respond and also custom ones... emojis for
/// custom should be free but text then custom").
public enum Reaction {
    /// On offer without opening a keyboard. Six fits a phone row at the default
    /// text size; the two that a push notification can also send are in here.
    public static let presets = ["🔥", "😂", "🤤", "🏃", "😩", "🎉"]

    /// Characters, counted the way a person would: a skin-toned emoji is one.
    public static let maxLength = 24

    /// Trimmed to a single line, collapsed whitespace, capped. Nil when nothing
    /// is left. Emoji and words go through the same door on purpose — the
    /// difference is only how it reads, not how it is stored.
    public static func normalize(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let text = words.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxLength))
    }

    /// True when the whole reaction is emoji, which is what lets the feed row
    /// show it bare instead of as a pill of text.
    public static func isAllEmoji(_ reaction: String) -> Bool {
        !reaction.isEmpty && reaction.allSatisfy { $0.isEmoji }
    }

    /// What a feed pill shows: an emoji as it is, words clipped so one mate's
    /// essay cannot push the row's other controls off the edge.
    public static func short(_ reaction: String, limit: Int = 12) -> String {
        if isAllEmoji(reaction) { return reaction }
        return reaction.count <= limit ? reaction : String(reaction.prefix(limit - 1)) + "…"
    }
}

extension Character {
    /// A character that presents as emoji: either it is emoji by default, or it
    /// carries the variation selector that makes it so (❤️ against ❤).
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        if unicodeScalars.count > 1 && unicodeScalars.contains(where: { $0.properties.isEmoji }) {
            return true
        }
        return scalar.properties.isEmojiPresentation
    }
}
