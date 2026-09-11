import Foundation

public enum Username {
    /// Lowercased valid username or nil. Rules: 3–15 chars, [a-z0-9_], starts with a letter.
    public static func normalize(_ raw: String) -> String? {
        let c = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (3...15).contains(c.count),
              let first = c.first, first.isASCII, first.isLetter,
              c.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" })
        else { return nil }
        return c
    }
}

/// The nickname ("bijnaam") shown on feed rows, pushes and group member lists.
/// Free text, unlike the username: trimmed, inner whitespace collapsed, 1–30
/// characters. Same bounds on the server (`changeDisplayNameCore`).
public enum DisplayName {
    public static let maxLength = 30
    public static func normalize(_ raw: String) -> String? {
        let words = raw.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let c = words.joined(separator: " ")
        guard (1...maxLength).contains(c.count) else { return nil }
        return c
    }
}
