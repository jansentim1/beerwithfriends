import BeerKit
import SwiftUI
import UIKit

// COMPILE-PARKED (Task 10 follow-up): no Xcode on this machine — written against
// iOS 17 SDK APIs, not yet compiled.

// The drinks half of the visual system: every glass is DRAWN, never an image, so
// it can fill on tap (Theme.pour) and drain over the 24 h life of a beer.
// Vocabulary (docs/design/direction.md): a 2 pt outline in `primary` at 55 %, a
// 5 % `primary` glass fill, and one explicit liquid colour per drink so the
// content reads as the drink itself in both schemes.
//
// Geometry lives in a unit box (0…1 in x and y, y down) that is scaled to the
// view's frame, so one set of numbers serves the 72 pt picker and the 44 pt feed
// glass. Horizontal extent of the liquid is decided by CLIPPING to the glass
// silhouette — the liquid itself is a full-width rectangle — which is why only
// the vertical span of the cavity ("bowl") is tabulated per kind.

// MARK: - View

/// One glass, filled to `level` (0 = empty, 1 = to the brim). `size` is the
/// height; the width follows the kind's proportions. Decorative by itself: the
/// caller owns the VoiceOver label (see HomeView's feed row).
struct DrinkGlassView: View {
    let kind: DrinkKind
    var level: Double
    var size: CGFloat = 72

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fill = min(max(level, 0), 1)
        // 2 pt at the picker's 72 pt, 1.2 pt at the feed's 44 pt: the outline
        // keeps its weight relative to the glass instead of going clumsy small.
        let lineWidth = max(1, size * 0.028)
        let outline = Color.primary.opacity(0.55)

        return ZStack {
            GlassShape(kind: kind)
                .fill(Color.primary.opacity(0.05))

            // Liquid, foam and bubbles are clipped to the silhouette as one
            // layer, so the taper of the glass shapes the drink.
            ZStack {
                LiquidShape(kind: kind, level: fill)
                    .fill(DrinkGlassPalette.liquid(kind))
                if kind == .pils || kind == .special {
                    FoamShape(kind: kind, level: fill)
                        .fill(DrinkGlassPalette.foam)
                }
                if kind == .bubbles {
                    BubblesShape(kind: kind, level: fill)
                        .fill(Color.white.opacity(0.75))
                }
            }
            .clipShape(GlassShape(kind: kind))

            GlassShape(kind: kind)
                .stroke(outline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            // Stems, feet and the soft drink's straw: stroked only, never filled.
            GlassDecorationShape(kind: kind)
                .stroke(outline, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size * DrinkGlassGeometry.widthRatio(kind), height: size)
        // The pour: a change of `level` animates the liquid (and the foam that
        // rides on it). Reduce Motion cuts it to the 180 ms state change.
        .animation(reduceMotion ? Theme.quick : Theme.pour, value: fill)
        .accessibilityHidden(true)
    }
}

// MARK: - Picker

/// The hero of Home: seven glasses, "empty-ish", one tap each, in the canonical
/// `DrinkKind` order — the row never reshuffles, so the glass you reach for is
/// always in the same place. Tapping pours the glass full over `Theme.pour` and
/// hands the kind to `onPick`; the glass then STAYS full and drains with the
/// drink, because `currentDrink` / `currentLevel` follow the row that just
/// arrived in the feed (Tim: "the pour animation should not then clear, but it
/// should also prevent someone from spamming the button"). The last drink you
/// picked keeps a soft amber tile.
///
/// The spam half of that sentence is `isLocked`: for the minute after a drink,
/// a tap logs nothing — it fires a warning haptic, shakes the cell, and calls
/// `onLockedTap` so the caller can say why in its caption.
///
/// `accessory` is one extra cell appended after the glasses, inside the same
/// scrolling row (Home puts the camera shortcut there), so the row reads as one
/// set of choices rather than a row plus a stray button underneath.
struct DrinkPickerView<Accessory: View>: View {
    @Binding var selected: DrinkKind?
    var isBusy: Bool = false
    /// What the user is drinking right now (their latest own row in the feed),
    /// and how full that glass is — `nil` when they have nothing on the go.
    var currentDrink: DrinkKind?
    /// Live fill of `currentDrink`: 1.0 the moment it is logged, draining over
    /// the 24 hours. Ignored when `currentDrink` is nil.
    var currentLevel: Double = 0
    /// True while the one-minute cooldown after the last drink is running.
    var isLocked: Bool = false
    let onPick: (DrinkKind) -> Void
    /// Called instead of `onPick` when a locked glass is tapped.
    var onLockedTap: () -> Void = {}
    @ViewBuilder var accessory: () -> Accessory

    /// Cell metrics: seven glasses at 62 pt on a 2 pt gap put the sixth glass
    /// half past the trailing edge on the narrowest iPhone, which is what tells
    /// you the row scrolls. Paging is view-aligned so a flick lands on a glass.
    // Sized so that, next to a 56 pt camera cell, four glasses fit and the fifth
    // peeks by ~20 pt: the row visibly continues.
    private static var cellMinWidth: CGFloat { 66 }
    private static var cellSpacing: CGFloat { 2 }

    @AppStorage("lastDrink") private var lastDrink = DrinkKind.pils.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The glass just tapped (one at a time). A bridge only: it holds the glass
    /// full for the instant between the tap and the optimistic feed row landing
    /// in `currentDrink`, which then owns the level for good.
    @State private var poured: DrinkKind?
    /// One shake counter per kind: bumping a cell's own count is what fires its
    /// keyframes, so a locked tap never twitches the glass next door.
    @State private var shakes: [DrinkKind: Int] = [:]

    private var favourite: DrinkKind {
        selected ?? DrinkKind(rawValue: lastDrink) ?? .pils
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .bottom, spacing: Self.cellSpacing) {
                ForEach(DrinkKind.allCases, id: \.self) { kind in
                    glass(kind)
                }
                // The accessory wears the same cell chrome as a glass, so it
                // bottom-aligns with the labels instead of floating.
                accessory()
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)
            }
            .scrollTargetLayout()
            .padding(.vertical, 4)
            .padding(.trailing, 12)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .opacity(isBusy ? 0.5 : 1)
        .animation(Theme.quick, value: isBusy)
        // The optimistic row has landed: the parent's level owns the glass from
        // here, so drop the local bridge rather than keep a glass pinned full.
        .onChange(of: currentDrink) { _, _ in
            poured = nil
        }
    }

    /// The parent's live level wins wherever it applies: the glass you are
    /// drinking stays full and drains, every other glass rests.
    private func displayLevel(for kind: DrinkKind) -> Double {
        if kind == currentDrink { return currentLevel }
        if kind == poured { return 1 }
        return kind.restingLevel
    }

    private func glass(_ kind: DrinkKind) -> some View {
        let isFavourite = kind == favourite
        let level: Double = displayLevel(for: kind)

        return Button {
            pick(kind)
        } label: {
            VStack(spacing: 4) {
                DrinkGlassView(kind: kind, level: level, size: 72)
                    .frame(width: 56, height: 72, alignment: .bottom)
                Text(kind.label)
                    .font(.caption)
                    .foregroundStyle(isFavourite ? Theme.accentInk : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 6)
            // Comfortably past the 44 pt minimum in both directions.
            .frame(minWidth: Self.cellMinWidth)
            .background {
                if isFavourite {
                    // Wash only: a ring on a 62 pt tile reads as a text field.
                    RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous)
                        .fill(Theme.accentSoft)
                }
            }
            .contentShape(Rectangle())
            // The cell leaving the viewport dims as a whole (glass + label), so
            // the peek reads as "more this way", not as a severed word.
            .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                content.opacity(phase.isIdentity ? 1 : 0.45)
            }
        }
        // Plain: the glass IS the button, no system tint or dimming on top of it.
        .buttonStyle(.plain)
        // Only an upload disables the row. A locked glass stays tappable on
        // purpose: the tap is what tells you why nothing happened.
        .disabled(isBusy)
        .lockedShake(trigger: shakes[kind] ?? 0)
        // The pils glass keeps `home.log` — it is the identifier the screenshot
        // UI test taps, and an element carries exactly one identifier.
        .accessibilityIdentifier(kind == .pils ? "home.log" : "home.drink.\(kind.rawValue)")
        .accessibilityLabel("I'm having \(kind.pushPhrase)")
        // No `.isSelected` trait: the tile marks the last drink, it is not a
        // selection you are sitting in.
        .accessibilityHint(lockedHint ?? (isFavourite ? "Your last one" : "Tells your mates, with this glass on your row"))
    }

    /// While the cooldown runs, every glass says so before you tap it.
    private var lockedHint: String? {
        isLocked ? "Locked for a minute after logging" : nil
    }

    private func pick(_ kind: DrinkKind) {
        // Anti-spam: one drink a minute. Nothing is logged and nothing is
        // remembered as your pick — the cell just shakes back at you.
        if isLocked {
            Haptics.warning()
            shakes[kind, default: 0] += 1
            onLockedTap()
            return
        }
        Haptics.success()
        selected = kind
        lastDrink = kind.rawValue
        // The pour is the whole gesture: the glass fills and STAYS full, because
        // the row this logs immediately becomes `currentDrink` at level 1.
        withAnimation(reduceMotion ? Theme.quick : Theme.pour) { poured = kind }
        onPick(kind)
    }
}

/// Convenience for the common case (no accessory cell): the previews and any
/// caller that just wants the seven glasses.
extension DrinkPickerView where Accessory == EmptyView {
    init(
        selected: Binding<DrinkKind?>,
        isBusy: Bool = false,
        currentDrink: DrinkKind? = nil,
        currentLevel: Double = 0,
        isLocked: Bool = false,
        onPick: @escaping (DrinkKind) -> Void,
        onLockedTap: @escaping () -> Void = {}
    ) {
        self.init(
            selected: selected,
            isBusy: isBusy,
            currentDrink: currentDrink,
            currentLevel: currentLevel,
            isLocked: isLocked,
            onPick: onPick,
            onLockedTap: onLockedTap,
            accessory: { EmptyView() }
        )
    }
}

// MARK: - Locked feedback

/// The warning notification haptic, which `Theme.Haptics` does not carry: it
/// exists for exactly one thing in this app — a tap that was refused.
extension Haptics {
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}

/// "No." A cell that refuses a tap shakes ±6 pt over 0.35 s, fired by bumping
/// `trigger` (so each cell owns its own counter). Under Reduce Motion the same
/// refusal reads as a quick blink instead of a slide — no travel, same beat.
struct LockedShakeModifier: ViewModifier {
    var trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceMotion {
            content.keyframeAnimator(initialValue: 1.0, trigger: trigger) { view, opacity in
                view.opacity(opacity)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(0.45, duration: 0.10)
                    LinearKeyframe(1.0, duration: 0.15)
                }
            }
        } else {
            content.keyframeAnimator(initialValue: CGFloat(0), trigger: trigger) { view, offset in
                view.offset(x: offset)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-6, duration: 0.09)
                    CubicKeyframe(6, duration: 0.09)
                    CubicKeyframe(-6, duration: 0.09)
                    CubicKeyframe(0, duration: 0.08)
                }
            }
        }
    }
}

extension View {
    /// Shakes this view once every time `trigger` changes (see
    /// `LockedShakeModifier`). Home uses it on the camera cell too.
    func lockedShake(trigger: Int) -> some View {
        modifier(LockedShakeModifier(trigger: trigger))
    }
}

// MARK: - Resting level

extension DrinkKind {
    /// What "empty-ish" means for this glass. One number for all seven read as
    /// a dry smear in the wide shapes (a martini is nearly all rim) and as a
    /// full pint in the narrow ones, so the resting splash is tuned per kind:
    /// enough liquid to name the drink by its colour at 44 pt, never enough to
    /// be mistaken for a glass someone is already drinking.
    var restingLevel: Double {
        switch self {
        case .pils: return 0.18
        case .special: return 0.28
        case .wine: return 0.32
        case .bubbles: return 0.30
        case .cocktail: return 0.45
        case .whisky: return 0.25
        case .soft: return 0.18
        }
    }
}

// MARK: - Shapes

/// The silhouette that holds liquid (bowl only — stems and feet are decoration).
private struct GlassShape: Shape {
    let kind: DrinkKind
    func path(in rect: CGRect) -> Path { DrinkGlassGeometry.bowlPath(kind, in: rect) }
}

/// Stems, feet and straws: stroked lines that never hold liquid.
private struct GlassDecorationShape: Shape {
    let kind: DrinkKind
    func path(in rect: CGRect) -> Path { DrinkGlassGeometry.decorationPath(kind, in: rect) }
}

/// A full-width slab from the bottom of the cavity up to the surface; the glass
/// silhouette clips it into shape. `level` is animatable, which is what makes
/// the pour (and the 24 h drain) a real animation rather than a jump.
private struct LiquidShape: Shape {
    let kind: DrinkKind
    var level: Double
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let surface = DrinkGlassGeometry.surfaceY(kind, level: level, in: rect)
        let bottom = DrinkGlassGeometry.cavity(kind, in: rect).maxY
        guard bottom > surface else { return Path() }
        return Path(CGRect(x: rect.minX, y: surface, width: rect.width, height: bottom - surface))
    }
}

/// The head on a pils or a special: a white band riding the liquid surface.
private struct FoamShape: Shape {
    let kind: DrinkKind
    var level: Double
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }
    func path(in rect: CGRect) -> Path {
        // No head on a glass that is barely wet (the resting picker state), and
        // the threshold is that kind's own resting level — a special beer rests
        // deeper than a pils.
        guard level > kind.restingLevel + 0.05 else { return Path() }
        let surface = DrinkGlassGeometry.surfaceY(kind, level: level, in: rect)
        let thickness = max(2, rect.height * 0.07)
        // The band sits entirely BELOW the surface: riding it half-out leaves a
        // white sliver hanging in the empty glass at low fills.
        let band = CGRect(x: rect.minX, y: surface,
                          width: rect.width, height: thickness)
        return Path(roundedRect: band, cornerRadius: thickness * 0.45)
    }
}

/// Three bubbles standing in the flute. Deliberately static: a repeating
/// animation in every feed row is a battery bill, and three sizes climbing the
/// glass already read as rising.
private struct BubblesShape: Shape {
    let kind: DrinkKind
    var level: Double
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }
    func path(in rect: CGRect) -> Path {
        guard level > 0.2 else { return Path() }
        let surface = DrinkGlassGeometry.surfaceY(kind, level: level, in: rect)
        let bottom = DrinkGlassGeometry.cavity(kind, in: rect).maxY
        let column = bottom - surface
        let spots: [(x: CGFloat, rise: CGFloat, radius: CGFloat)] = [
            (0.44, 0.28, 0.030),
            (0.57, 0.54, 0.022),
            (0.48, 0.78, 0.015),
        ]
        var path = Path()
        for spot in spots {
            let radius = max(0.6, rect.height * spot.radius)
            let centre = CGPoint(x: rect.minX + spot.x * rect.width,
                                y: bottom - column * spot.rise)
            path.addEllipse(in: CGRect(x: centre.x - radius, y: centre.y - radius,
                                       width: radius * 2, height: radius * 2))
        }
        return path
    }
}

// MARK: - Geometry

private enum DrinkGlassGeometry {
    /// Width of the drawing box as a fraction of its height: a pint is stocky, a
    /// flute is a sliver, a martini is wide at the rim.
    static func widthRatio(_ kind: DrinkKind) -> CGFloat {
        switch kind {
        case .pils: return 0.56
        case .special: return 0.66
        case .wine: return 0.60
        case .bubbles: return 0.42
        case .cocktail: return 0.64
        case .whisky: return 0.62
        case .soft: return 0.48
        }
    }

    /// Vertical span of the liquid cavity, as fractions of the box height.
    /// (Its horizontal extent comes from clipping to the silhouette.)
    static func bowl(_ kind: DrinkKind) -> (top: CGFloat, bottom: CGFloat) {
        switch kind {
        case .pils: return (0.02, 0.97)
        case .special: return (0.05, 0.55)
        case .wine: return (0.04, 0.52)
        case .bubbles: return (0.03, 0.57)
        case .cocktail: return (0.06, 0.52)
        case .whisky: return (0.42, 0.97)
        case .soft: return (0.05, 0.97)
        }
    }

    static func cavity(_ kind: DrinkKind, in rect: CGRect) -> CGRect {
        let span = bowl(kind)
        return CGRect(x: rect.minX, y: rect.minY + span.top * rect.height,
                      width: rect.width, height: (span.bottom - span.top) * rect.height)
    }

    /// Where the surface of the drink sits for a given fill level.
    static func surfaceY(_ kind: DrinkKind, level: Double, in rect: CGRect) -> CGFloat {
        let cavity = cavity(kind, in: rect)
        let fill = CGFloat(min(max(level, 0), 1))
        return cavity.maxY - cavity.height * fill
    }

    static func bowlPath(_ kind: DrinkKind, in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .pils:
            // Tall tapered pint, softened at the base.
            path.move(to: p(0.07, 0.02, rect))
            path.addLine(to: p(0.93, 0.02, rect))
            path.addLine(to: p(0.80, 0.92, rect))
            path.addQuadCurve(to: p(0.72, 0.97, rect), control: p(0.79, 0.97, rect))
            path.addLine(to: p(0.28, 0.97, rect))
            path.addQuadCurve(to: p(0.20, 0.92, rect), control: p(0.21, 0.97, rect))
            path.closeSubpath()
        case .special:
            // Chalice: a wide, shallow bowl on a short stem. Deliberately NOT a
            // tulip — at 44 pt a tulip and the wine glass are the same drawing,
            // and beer vs wine has to read from the silhouette alone.
            path.move(to: p(0.05, 0.04, rect))
            path.addLine(to: p(0.95, 0.04, rect))
            path.addCurve(to: p(0.62, 0.55, rect),
                          control1: p(0.93, 0.32, rect), control2: p(0.81, 0.55, rect))
            path.addQuadCurve(to: p(0.38, 0.55, rect), control: p(0.50, 0.58, rect))
            path.addCurve(to: p(0.05, 0.04, rect),
                          control1: p(0.19, 0.55, rect), control2: p(0.07, 0.32, rect))
            path.closeSubpath()
        case .wine:
            // Stemmed bowl: a rounded U under a wide rim.
            path.move(to: p(0.08, 0.04, rect))
            path.addCurve(to: p(0.50, 0.52, rect),
                          control1: p(0.09, 0.34, rect), control2: p(0.24, 0.52, rect))
            path.addCurve(to: p(0.92, 0.04, rect),
                          control1: p(0.76, 0.52, rect), control2: p(0.91, 0.34, rect))
            path.closeSubpath()
        case .bubbles:
            // Flute: narrow, near-straight, rounded at the bottom.
            path.move(to: p(0.20, 0.03, rect))
            path.addCurve(to: p(0.38, 0.52, rect),
                          control1: p(0.23, 0.28, rect), control2: p(0.34, 0.42, rect))
            path.addQuadCurve(to: p(0.62, 0.52, rect), control: p(0.50, 0.60, rect))
            path.addCurve(to: p(0.80, 0.03, rect),
                          control1: p(0.66, 0.42, rect), control2: p(0.77, 0.28, rect))
            path.closeSubpath()
        case .cocktail:
            // Martini: a straight-sided cone.
            path.move(to: p(0.03, 0.06, rect))
            path.addLine(to: p(0.97, 0.06, rect))
            path.addLine(to: p(0.53, 0.50, rect))
            path.addQuadCurve(to: p(0.47, 0.50, rect), control: p(0.50, 0.53, rect))
            path.closeSubpath()
        case .whisky:
            // Tumbler: short, barely tapered, heavy rounded base.
            path.move(to: p(0.13, 0.42, rect))
            path.addLine(to: p(0.87, 0.42, rect))
            path.addLine(to: p(0.84, 0.90, rect))
            path.addQuadCurve(to: p(0.75, 0.97, rect), control: p(0.84, 0.97, rect))
            path.addLine(to: p(0.25, 0.97, rect))
            path.addQuadCurve(to: p(0.16, 0.90, rect), control: p(0.16, 0.97, rect))
            path.closeSubpath()
        case .soft:
            // Tall straight glass (the straw is decoration).
            path.move(to: p(0.20, 0.05, rect))
            path.addLine(to: p(0.80, 0.05, rect))
            path.addLine(to: p(0.80, 0.91, rect))
            path.addQuadCurve(to: p(0.71, 0.97, rect), control: p(0.80, 0.97, rect))
            path.addLine(to: p(0.29, 0.97, rect))
            path.addQuadCurve(to: p(0.20, 0.91, rect), control: p(0.20, 0.97, rect))
            path.closeSubpath()
        }
        return path
    }

    static func decorationPath(_ kind: DrinkKind, in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .pils, .whisky:
            break // nothing under the glass
        case .special:
            addStem(&path, in: rect, top: 0.55, halfWidth: 0.055, footWidth: 0.46, footY: 0.94)
        case .wine:
            addStem(&path, in: rect, top: 0.52, halfWidth: 0.035, footWidth: 0.54, footY: 0.94)
        case .bubbles:
            addStem(&path, in: rect, top: 0.56, halfWidth: 0.055, footWidth: 0.66, footY: 0.94)
        case .cocktail:
            addStem(&path, in: rect, top: 0.50, halfWidth: 0.030, footWidth: 0.44, footY: 0.94)
        case .soft:
            // Bendy straw: a short elbow above the rim, then down into the glass.
            path.move(to: p(0.93, 0.04, rect))
            path.addLine(to: p(0.64, 0.14, rect))
            path.addLine(to: p(0.44, 0.86, rect))
        }
        return path
    }

    /// Two stem lines down to a foot drawn as one round-capped line — it stays
    /// legible at 44 pt, where a stroked ellipse turns to mush.
    private static func addStem(_ path: inout Path, in rect: CGRect,
                                top: CGFloat, halfWidth: CGFloat,
                                footWidth: CGFloat, footY: CGFloat) {
        path.move(to: p(0.5 - halfWidth, top, rect))
        path.addLine(to: p(0.5 - halfWidth, footY, rect))
        path.move(to: p(0.5 + halfWidth, top, rect))
        path.addLine(to: p(0.5 + halfWidth, footY, rect))
        path.move(to: p(0.5 - footWidth / 2, footY, rect))
        path.addLine(to: p(0.5 + footWidth / 2, footY, rect))
    }

    /// Unit box (0…1, y down) → the view's rect.
    private static func p(_ x: CGFloat, _ y: CGFloat, _ rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }
}

// MARK: - Palette

/// The drinks are the only place in the app with colours beyond Pint Amber, and
/// they are content, not chrome: each one is an explicit, scheme-aware liquid.
private enum DrinkGlassPalette {
    static func liquid(_ kind: DrinkKind) -> Color {
        switch kind {
        case .pils: return Theme.accent          // pint amber, the house colour
        case .special: return special
        case .wine: return wine
        case .bubbles: return bubbles
        case .cocktail: return cocktail
        case .whisky: return whisky
        case .soft: return soft
        }
    }

    /// Deep amber: a dubbel or a bock.
    static let special = paired(light: (0.55, 0.22, 0.03), dark: (0.72, 0.33, 0.08))
    /// Burgundy, lifted in dark mode so it never reads as a hole in the glass.
    static let wine = paired(light: (0.45, 0.08, 0.19), dark: (0.62, 0.13, 0.27))
    /// Pale gold.
    static let bubbles = paired(light: (0.93, 0.82, 0.50), dark: (0.96, 0.87, 0.58))
    /// Pale green.
    static let cocktail = paired(light: (0.60, 0.81, 0.56), dark: (0.66, 0.87, 0.62))
    /// Caramel.
    static let whisky = paired(light: (0.74, 0.44, 0.11), dark: (0.85, 0.54, 0.18))
    /// Cola brown.
    static let soft = paired(light: (0.28, 0.15, 0.09), dark: (0.56, 0.34, 0.21))
    /// The head: cream rather than pure white, so it reads on both grounds.
    static let foam = paired(light: (0.99, 0.98, 0.94), dark: (0.94, 0.92, 0.87))

    private static func paired(light: (CGFloat, CGFloat, CGFloat),
                               dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(UIColor { trait in
            let rgb = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}

// MARK: - Previews

#Preview("Glasses") {
    ScrollView {
        VStack(spacing: 24) {
            ForEach([0.15, 0.5, 1.0], id: \.self) { level in
                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(DrinkKind.allCases, id: \.self) { kind in
                        DrinkGlassView(kind: kind, level: level, size: 72)
                    }
                }
            }
            // Free to tap, nothing on the go.
            DrinkPickerView(selected: .constant(nil), isBusy: false, onPick: { _ in })
            // Mid-cooldown: the wine glass stays nearly full, the rest rest.
            DrinkPickerView(
                selected: .constant(.wine),
                isBusy: false,
                currentDrink: .wine,
                currentLevel: 0.96,
                isLocked: true,
                onPick: { _ in },
                onLockedTap: {}
            )
        }
        .padding()
    }
}
