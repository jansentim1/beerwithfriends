import BeerKit
import FirebaseCore
import FirebaseMessaging
import SwiftUI
import UIKit
import UserNotifications

// COMPILE-PARKED (Task 9): no Xcode on this machine — written against
// Firebase iOS SDK 11 + BeerKit protocol signatures, not yet compiled.

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()
        EmulatorConfig.applyIfRequested()
        Theme.installNavigationBarAppearance()
        // Set here, not on permission grant: a notification action tapped on a
        // cold launch is delivered to the delegate right after this returns.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // Hand the APNs token to FCM so it can mint/refresh the registration token.
        Messaging.messaging().apnsToken = deviceToken
        PushRegistrar.shared.apnsTokenDidArrive(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushRegistrar.shared.apnsRegistrationFailed(error)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// A mate's beer is the whole point of the app: show it even in the
    /// foreground (iOS suppresses pushes by default while the app is active).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Quick replies from the notification itself. The write needs a signed-in
    /// `BeerServicing`, which may not exist yet (cold launch), so the action is
    /// queued on ReactionInbox and AppState drains it. Completing immediately is
    /// safe: iOS grants a background action ~30 s and Firestore queues the write
    /// offline, so nothing is lost by not waiting for the round-trip here.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let beerId = response.notification.request.content.userInfo["beerId"] as? String
        let action: ReactionAction?
        switch response.actionIdentifier {
        case "CHEERS": action = .cheers
        case "ONMYWAY": action = .reply(.onMyWay)
        case "JEALOUS": action = .reply(.jealous)
        default: action = nil // plain tap (opens the app) or dismiss: nothing to write
        }
        if let beerId, let action {
            ReactionInbox.shared.enqueue(ReactionInbox.Item(beerId: beerId, action: action))
        }
        completionHandler()
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
                // pubdates://add/<username> — hand the name to FriendsView and
                // bring that tab forward.
                .onOpenURL { url in
                    if let code = MateLink.groupCode(fromDeepLink: url) {
                        appState.pendingGroupCode = code
                        NotificationCenter.default.post(name: .pubDatesSwitchToGroups, object: nil)
                    } else if let name = MateLink.username(fromDeepLink: url) {
                        // Sticky: FriendsView consumes it on appear, so a cold launch
                        // (tab not built yet) or a launch into onboarding still works.
                        appState.pendingMateUsername = name
                        NotificationCenter.default.post(name: .pubDatesSwitchToFriends, object: nil)
                    }
                }
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

    private enum Tab: Hashable { case beers, friends, map, settings }
    @State private var selectedTab: Tab = .beers

    var body: some View {
        // Non-nil exactly while phase == .ready (see AppState).
        if let beerService = appState.beerService, let friendService = appState.friendService {
            TabView(selection: $selectedTab) {
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
                .tag(Tab.beers)

                FriendsView(profile: profile, friendService: friendService)
                    .tabItem { Label("Mates", systemImage: "person.2.fill") }
                    .tag(Tab.friends)

                MapView(profile: profile, beerService: beerService)
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(Tab.map)

                SettingsView(profile: profile)
                    .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                    .tag(Tab.settings)
            }
            .tint(Theme.accent)
            // Home's empty state offers "Add a mate"; it posts this to switch tabs.
            .onReceive(NotificationCenter.default.publisher(for: .pubDatesSwitchToFriends)) { _ in
                selectedTab = .friends
            }
        } else {
            ProgressView() // unreachable in practice; keeps the wiring total
        }
    }
}
