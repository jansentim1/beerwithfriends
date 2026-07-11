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
