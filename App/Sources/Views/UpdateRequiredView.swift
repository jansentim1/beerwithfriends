import SwiftUI

/// The dead end an out-of-date build gets. TestFlight has no way to force an
/// update, so the app refuses to run below the floor the server publishes
/// (`config/app.minBuild`) and sends people to TestFlight to fetch the build.
/// Only ever shown when that read succeeded and said no — see `VersionGate`.
struct UpdateRequiredView: View {
    private let testFlight = URL(string: "https://testflight.apple.com/join/1QfbyRt9")!

    var body: some View {
        VStack(spacing: 14) {
            Text("🍺")
                .font(.system(size: 56))
                .accessibilityHidden(true)
            Text("Time for a fresh one")
                .font(Theme.displayTitle2)
                .multilineTextAlignment(.center)
            Text("This version of PubDates is too old to keep up with your mates. Grab the latest from TestFlight and you're back in.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: testFlight) {
                Text("Open TestFlight")
            }
            .buttonStyle(HeroButtonStyle())
            .accessibilityIdentifier("update.openTestFlight")
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}
