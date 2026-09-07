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
        PushRegistrar.shared.apnsTokenDidArrive()
    }
}

@main
struct BeerWithFriendsApp: App {
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

/// Routes on `AppState.phase` (Task 10: real screens).
struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        switch appState.phase {
        case .loading:
            ProgressView("Pouring…")
        case .signedOut, .needsUsername, .profileUnavailable:
            OnboardingView()
        case .ready(let profile):
            MainTabView(profile: profile)
                .id(profile.id) // fresh view state (and HomeViewModel) per account
        }
    }
}

/// Tab shell for the signed-in app. Views consume only BeerKit protocols +
/// AppState; the one concrete-type touch (screenshot receipts, which the
/// frozen `BeerServicing` protocol doesn't cover) is wired HERE as a closure
/// so HomeView/PhotoViewerView stay Firebase-free.
private struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    let profile: UserProfile

    var body: some View {
        // Non-nil exactly while phase == .ready (see AppState).
        if let beerService = appState.beerService, let friendService = appState.friendService {
            TabView {
                HomeView(
                    profile: profile,
                    beerService: beerService,
                    friendService: friendService,
                    screenshotReporter: { beerId in
                        await (beerService as? FirebaseBeerService)?
                            .recordScreenshot(beerId: beerId)
                    }
                )
                .tabItem { Label("Beers", systemImage: "mug.fill") }

                FriendsView(profile: profile, friendService: friendService)
                    .tabItem { Label("Friends", systemImage: "person.2.fill") }

                SettingsView(profile: profile)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
            }
        } else {
            ProgressView() // unreachable in practice; keeps the wiring total
        }
    }
}
