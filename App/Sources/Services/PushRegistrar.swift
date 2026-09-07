import FirebaseFirestore
import FirebaseMessaging
import Foundation
import UIKit
import UserNotifications

// COMPILE-PARKED (Task 9): no Xcode on this machine — written against
// Firebase iOS SDK 11 + BeerKit protocol signatures, not yet compiled.

/// Requests notification permission, registers with APNs/FCM, and keeps the
/// FCM token in `users/{uid}/private/push` (field `token`) — NOT on the public
/// user doc, so other users can't scrape it. Handles the token arriving before
/// sign-in completes by caching it and flushing once a uid is set.
final class PushRegistrar: NSObject, MessagingDelegate, @unchecked Sendable {
    /// One instance: the AppDelegate feeds it the APNs token, AppState binds the user.
    static let shared = PushRegistrar()

    private let lock = NSLock()
    private var uid: String?
    private var lastToken: String?
    private var lastApnsToken: String?
    private var didStart = false

    /// Ask permission + register. Called by AppState once the user is `.ready`
    /// (avoids prompting mid-onboarding). Safe to call repeatedly.
    func startRegistration() {
        lock.lock()
        let alreadyStarted = didStart
        didStart = true
        lock.unlock()
        guard !alreadyStarted else { return }

        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { granted, _ in
            guard granted else { return }
            // Task { @MainActor } (not DispatchQueue.main.async): the completion
            // handler is nonisolated, and only hopping actors satisfies Swift 6's
            // isolation checking for the MainActor-only UIApplication API.
            Task { @MainActor in
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Best-effort removal of the stored token for the CURRENT user. Must be
    /// called while still authenticated (rules only allow the owner to touch
    /// `users/{uid}/private/*`) — i.e. before Auth.signOut()/account deletion —
    /// or a reused device keeps receiving the previous account's pushes.
    func clearToken() async {
        // withLock (not lock()/unlock()): the latter are unavailable in async contexts.
        guard let boundUid = lock.withLock({ uid }) else { return }
        try? await Firestore.firestore()
            .document("users/\(boundUid)/private/push")
            .delete()
    }

    /// Bind (or unbind, with nil) the signed-in user. Flushes a token that
    /// arrived before sign-in.
    func setUser(uid: String?) {
        lock.lock()
        self.uid = uid
        let pendingToken = lastToken
        let pendingApns = lastApnsToken
        lock.unlock()
        if let uid, let pendingApns { writeApns(token: pendingApns, uid: uid) }
        if let uid, let pendingToken {
            write(token: pendingToken, uid: uid)
        } else if uid != nil {
            // The delegate only fires on mint/refresh. On every later launch the
            // cached token is delivered before the delegate exists, so ask for it.
            fetchToken()
        }
    }

    /// AppDelegate hook. The raw APNs token is stored too: the server delivers
    /// pushes straight to Apple with it (FCM delivery needs a console-only step).
    func apnsTokenDidArrive(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        lock.lock()
        lastApnsToken = hex
        let boundUid = uid
        lock.unlock()
        if let boundUid { writeApns(token: hex, uid: boundUid) }
        fetchToken()
    }

    private func writeApns(token: String, uid: String) {
        Firestore.firestore()
            .document("users/\(uid)/private/push")
            .setData(["apnsToken": token], merge: true) { error in
                if let error {
                    print("PushRegistrar: apns token write failed: \(error.localizedDescription)")
                }
            }
    }

    private func fetchToken() {
        Messaging.messaging().token { [weak self] token, error in
            guard let self, let token else {
                if let error { print("PushRegistrar: token fetch failed: \(error.localizedDescription)") }
                return
            }
            self.lock.lock()
            self.lastToken = token
            let boundUid = self.uid
            self.lock.unlock()
            if let boundUid {
                self.write(token: token, uid: boundUid)
            }
        }
    }

    // MARK: - MessagingDelegate

    /// Fires on initial token mint and every refresh.
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        lock.lock()
        lastToken = fcmToken
        let boundUid = uid
        lock.unlock()
        if let boundUid {
            write(token: fcmToken, uid: boundUid)
        }
    }

    private func write(token: String, uid: String) {
        Firestore.firestore()
            .document("users/\(uid)/private/push")
            .setData(["token": token], merge: true) { error in
                if let error {
                    // Best effort: pushes degrade gracefully; next refresh retries.
                    print("PushRegistrar: token write failed: \(error.localizedDescription)")
                }
            }
    }
}
