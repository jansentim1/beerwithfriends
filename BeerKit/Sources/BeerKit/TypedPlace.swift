import Foundation

/// The place you type when the app may not read your location (Tim, 2026-10-15:
/// "add a typed place when no location setting"; App Review 5.1.1(iv) asks for
/// a manual address when Location is declined). It goes on the drink as
/// `place` with no coordinate, so it never gets a map pin.
///
/// Firestore rules accept `place` as a string of 1 to 60 (`size()` counts
/// unicode scalars), so the cap here is `BeerLog.placeMaxLength` measured the
/// same way, through `BeerLog.clampPlace`.
public enum TypedPlace {
    public static var maxLength: Int { BeerLog.placeMaxLength }

    /// Trimmed, line breaks folded to spaces, runs of spaces collapsed. Returns
    /// nil when nothing is left or the text is over the cap: the Post button
    /// stays off rather than the name being cut behind your back.
    public static func normalize(_ raw: String) -> String? {
        let folded = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !folded.isEmpty else { return nil }
        guard BeerLog.clampPlace(folded) == folded else { return nil }
        return folded
    }

    /// True when `normalize` would give a place to post.
    public static func isValid(_ raw: String) -> Bool { normalize(raw) != nil }

    /// What the field accepts as you type: the cap applied live, so the caret
    /// simply stops at 60. Cut on grapheme boundaries, never half an emoji.
    public static func clampWhileTyping(_ raw: String) -> String {
        BeerLog.clampPlace(raw)
    }
}
