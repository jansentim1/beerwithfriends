#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// The text you can put on a photo, Snapchat-style (Tim, 2026-09-15: "je moet
/// teksten bij je foto kunnen plaatsen, van die snapchat stroken").
public enum Caption {
    public static let maxLength = 80
    public static let maxLines = 3

    /// Trimmed, blank lines collapsed, capped at `maxLength` characters and
    /// `maxLines` lines. Returns nil when nothing is left: no text, no strip.
    public static func normalize(_ raw: String) -> String? {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        // Leading and trailing blank lines go; one in the middle is a paragraph
        // break the writer meant.
        var kept = lines
        while kept.first?.isEmpty == true { kept.removeFirst() }
        while kept.last?.isEmpty == true { kept.removeLast() }
        guard !kept.isEmpty else { return nil }
        let text = kept.prefix(maxLines).joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        return String(text.prefix(maxLength))
    }

    /// What the field should accept as you type: the cap, applied live, so the
    /// caret simply stops rather than the text being rewritten under it.
    public static func clampWhileTyping(_ raw: String) -> String {
        var text = raw
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > maxLines {
            text = lines.prefix(maxLines).joined(separator: "\n")
        }
        return String(text.prefix(maxLength))
    }
}

/// Where the caption strip sits on a photo, in one place, so the overlay you
/// type on and the pixels that get uploaded agree. All fractions are of the
/// photo's own size, which is what makes the two agree at different scales.
public struct CaptionLayout: Equatable, Sendable {
    /// Strip height as a fraction of the photo height, for `lineCount` lines.
    public let stripHeight: CGFloat
    /// Strip top edge, as a fraction of the photo height.
    public let stripTop: CGFloat
    /// Type size as a fraction of the photo height.
    public let fontHeight: CGFloat

    /// Fractions tuned on a 390 × 844 screen: 20 pt type, 12 pt padding.
    static let fontFraction: CGFloat = 20.0 / 844.0
    static let linePadding: CGFloat = 5.0 / 844.0
    static let verticalPadding: CGFloat = 12.0 / 844.0

    /// `centre` is where the middle of the strip wants to sit, 0…1 down the
    /// photo; it is clamped so the whole strip stays on the photo.
    public init(lineCount: Int, centre: CGFloat) {
        let lines = CGFloat(max(1, min(Caption.maxLines, lineCount)))
        let line = Self.fontFraction + Self.linePadding
        stripHeight = lines * line + 2 * Self.verticalPadding
        let half = stripHeight / 2
        stripTop = min(max(centre, half), 1 - half) - half
        fontHeight = Self.fontFraction
    }

    /// The strip in a photo of `size`.
    public func stripRect(in size: CGSize) -> CGRect {
        CGRect(x: 0, y: stripTop * size.height, width: size.width, height: stripHeight * size.height)
    }
    /// Point size of the type in a photo of `size`.
    public func fontSize(in size: CGSize) -> CGFloat { fontHeight * size.height }
    /// Side padding, so long lines never touch the edge.
    public func horizontalInset(in size: CGSize) -> CGFloat { size.width * 0.05 }

    /// Where the strip starts out: below the middle, where Snapchat drops it.
    public static let defaultCentre: CGFloat = 0.62
    /// Snapchat's band, which is what Tim asked for (2026-09-17: "do snapchats").
    public static let stripOpacity: CGFloat = 0.5
}
