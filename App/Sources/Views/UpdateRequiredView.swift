import Foundation
import SwiftUI

/// The dead end an out-of-date build gets. Neither TestFlight nor the App Store
/// can force an update, so the app refuses to run below the floor the server
/// publishes (`config/app.minBuild`) and sends people to fetch the new build
/// from wherever this one came from: TestFlight for a TestFlight install, the
/// App Store page otherwise (App Review 2.1/2.3: a store build must not point
/// at TestFlight). Only ever shown when that read succeeded and said no — see
/// `VersionGate`.
struct UpdateRequiredView: View {
    private let testFlight = URL(string: "https://testflight.apple.com/join/1QfbyRt9")!
    private let appStore = URL(string: "https://apps.apple.com/app/id6809410863")!

    /// TestFlight installs carry a sandbox receipt; App Store installs carry a
    /// production one. DEBUG builds have no receipt at all and are treated like
    /// TestFlight, since that is where a developer gets the next build.
    private static var isTestFlight: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    private var destination: URL { Self.isTestFlight ? testFlight : appStore }
    private var message: String {
        Self.isTestFlight
            ? "This version of PubDates is too old to keep up with your mates. Grab the latest from TestFlight and you're back in."
            : "This version of PubDates is too old to keep up with your mates. Grab the update from the App Store and you're back in."
    }
    private var buttonTitle: String { Self.isTestFlight ? "Open TestFlight" : "Open the App Store" }

    var body: some View {
        VStack(spacing: 14) {
            Text("🍺")
                .font(.system(size: 56))
                .accessibilityHidden(true)
            Text("Time for a fresh one")
                .font(Theme.displayTitle2)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Link(destination: destination) {
                Text(buttonTitle)
            }
            .buttonStyle(HeroButtonStyle())
            .accessibilityIdentifier("update.openStore")
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .accessibilityElement(children: .contain)
    }
}
