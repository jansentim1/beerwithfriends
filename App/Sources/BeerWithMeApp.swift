import BeerKit
import FirebaseCore
import FirebaseMessaging
import SwiftUI
import UIKit

// COMPILE-PARKED (Task 9): no Xcode on this machine — written against
// Firebase iOS SDK 11 + BeerKit protocol signatures, not yet compiled.

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Hand the APNs token to FCM so it can mint/refresh the registration token.
        Messaging.messaging().apnsToken = deviceToken
    }
}

@main
struct BeerWithMeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { appState.start() }
        }
    }
}

/// Routes on `AppState.phase`. Every leaf below is a placeholder that
/// Task 10 replaces with the real screens (OnboardingView, HomeView, ...).
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.phase {
        case .loading:
            ProgressView("Pouring…") // Placeholder — Task 10 may restyle.
        case .signedOut:
            // Placeholder — replaced by OnboardingView (Sign in with Apple) in Task 10.
            Text("Signed out — OnboardingView lands in Task 10")
        case .needsUsername:
            // Placeholder — replaced by OnboardingView's username picker in Task 10.
            Text("Pick a username — OnboardingView lands in Task 10")
        case .ready(let profile):
            // Placeholder — replaced by HomeView (feed + log button) in Task 10.
            Text("🍺 Hello @\(profile.username) — HomeView lands in Task 10")
        }
    }
}
