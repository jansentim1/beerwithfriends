import SwiftUI
import UIKit

// The PubDates visual system. Durable decisions live in docs/design/direction.md and
// (after the finish review) DESIGN.md. Everything here is semantic and scheme-aware.

enum Theme {
    // MARK: Colour

    /// "Pint amber": the one committed accent. Tuned per scheme so it stays legible on
    /// white and on near-black (light ≈ #E68A00, dark ≈ #FFA733).
    static let accent = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.655, blue: 0.20, alpha: 1)
            : UIColor(red: 0.90, green: 0.54, blue: 0.00, alpha: 1)
    })
    /// Ink on top of the accent (the button label): always dark, it reads in both schemes.
    static let onAccent = Color(red: 0.16, green: 0.09, blue: 0.0)
    /// Soft amber wash for avatar circles and the sealed chip's background in quiet states.
    static let accentSoft = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.655, blue: 0.20, alpha: 0.18)
            : UIColor(red: 0.90, green: 0.54, blue: 0.00, alpha: 0.14)
    })
    static let surface = Color(.secondarySystemGroupedBackground)
    static let ground = Color(.systemGroupedBackground)

    // MARK: Shape

    static let heroRadius: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let chipRadius: CGFloat = 12

    // MARK: Type

    static func display(_ size: CGFloat = 34, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static let heroLabel: Font = .system(.title3, design: .rounded, weight: .bold)

    // MARK: Motion

    static let spring: Animation = .spring(response: 0.42, dampingFraction: 0.78)
    static let quick: Animation = .easeOut(duration: 0.18)
}

// MARK: - Haptics

enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
}

// MARK: - Button styles

/// The hero action: full-width, amber, rounded, presses down slightly. `isBusy` shows a
/// bottom-to-top "pour" sweep (Reduce Motion: crossfade) while a photo uploads.
struct HeroButtonStyle: ButtonStyle {
    var isBusy = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.heroLabel)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background {
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                        .fill(Theme.accent)
                    if isBusy {
                        RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                            .fill(.white.opacity(0.25))
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .animation(Theme.spring, value: isBusy)
    }
}

/// Round secondary action next to the hero (camera).
struct RoundIconButtonStyle: ButtonStyle {
    var size: CGFloat = 64
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.36, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Theme.accentSoft, in: Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

/// Pill for secondary actions and reactions (cheers, "view once").
struct PillButtonStyle: ButtonStyle {
    enum Emphasis { case filled, tinted, quiet }
    var emphasis: Emphasis = .tinted

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .background(background, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
    private var foreground: Color {
        switch emphasis {
        case .filled: return Theme.onAccent
        case .tinted: return Theme.accent
        case .quiet: return .secondary
        }
    }
    private var background: Color {
        switch emphasis {
        case .filled: return Theme.accent
        case .tinted: return Theme.accentSoft
        case .quiet: return Color(.tertiarySystemFill)
        }
    }
}

// MARK: - Components

/// Initials on an amber-tinted circle. No photos of people in this app, only beers.
struct AvatarView: View {
    let name: String
    var size: CGFloat = 48

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .background(Theme.accentSoft, in: Circle())
            .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }
        return letters.isEmpty ? "🍺" : letters.joined().uppercased()
    }
}

/// Quiet status pill (e.g. "seen").
struct StatusPill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 28)
            .background(Color(.tertiarySystemFill), in: Capsule())
    }
}

/// Section label used above groups in the feed and lists.
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}
