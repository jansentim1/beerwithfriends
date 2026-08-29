import BeerKit
import Combine
import FirebaseAuth
import FirebaseFirestore
import Foundation

// COMPILE-PARKED (Task 9): no Xcode on this machine — written against
// Firebase iOS SDK 11 + BeerKit protocol signatures, not yet compiled.

/// App-wide session state. Task 10 views consume `phase` plus the service
/// protocols exposed here — they never touch Firebase types directly.
@MainActor
final class AppState: ObservableObject {
    enum Phase: Equatable {
        case loading
        case signedOut
        case needsUsername
        case ready(UserProfile)
    }

    @Published private(set) var phase: Phase = .loading
    /// One-shot error copy for the active flow (sign-in / username claim / account).
    @Published var errorMessage: String?

    let authService: any AuthServicing = FirebaseAuthService()
    /// Non-nil exactly while `phase == .ready`.
    private(set) var beerService: (any BeerServicing)?
    private(set) var friendService: (any FriendServicing)?

    private let pushRegistrar = PushRegistrar()
    private var authListener: AuthStateDidChangeListenerHandle?

    /// Attach the Firebase auth listener. Call once from the root view's `.task`
    /// (after `FirebaseApp.configure()` has run in the AppDelegate).
    func start() {
        guard authListener == nil else { return }
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let uid = user?.uid
            Task { @MainActor [weak self] in
                await self?.handleAuthChange(uid: uid)
            }
        }
    }

    // MARK: - Flows driven by Task 10 views

    func signInWithApple(idToken: String, nonce: String) async {
        do {
            _ = try await authService.signInWithApple(idToken: idToken, nonce: nonce)
            // The auth state listener advances `phase`.
        } catch {
            errorMessage = "Sign in failed — try again."
        }
    }

    /// Normalizes and claims `rawUsername`. On success flips straight to `.ready`.
    func claimUsername(_ rawUsername: String, displayName: String) async {
        guard let username = Username.normalize(rawUsername) else {
            errorMessage = "Usernames are 3–15 characters: a–z, 0–9, _ — and start with a letter."
            return
        }
        do {
            let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let profile = try await authService.claimUsername(
                username, displayName: trimmedName.isEmpty ? username : trimmedName)
            becomeReady(profile)
        } catch UsernameClaimError.taken {
            errorMessage = "@\(username) is already taken — pick another."
        } catch {
            errorMessage = "Couldn't save your username — try again."
        }
    }

    /// Live availability check for the onboarding username picker (Task 10).
    /// `friendService` doesn't exist yet while `phase == .needsUsername`, so
    /// this reads the reservation doc directly (rules: any signed-in get).
    /// Returns nil when the lookup itself failed (offline etc.) — unknown.
    func isUsernameTaken(_ normalizedUsername: String) async -> Bool? {
        do {
            let snap = try await Firestore.firestore()
                .document("usernames/\(normalizedUsername)").getDocument()
            return snap.exists
        } catch {
            return nil
        }
    }

    func signOut() async {
        // While still authenticated: rules won't let us touch private/push after
        // sign-out, and a stale token would deliver this account's pushes to
        // whoever uses the device next.
        await pushRegistrar.clearToken()
        do {
            try authService.signOut()
            // The auth state listener flips `phase` to `.signedOut`.
        } catch {
            errorMessage = "Couldn't sign out — try again."
        }
    }

    func deleteAccount() async {
        await pushRegistrar.clearToken()
        do {
            try await authService.deleteAccount()
            // Server erased data + auth user; the listener flips to `.signedOut`.
        } catch {
            errorMessage = "Couldn't delete your account — try again."
        }
    }

    // MARK: - Auth state

    private func handleAuthChange(uid: String?) async {
        guard let uid else {
            beerService = nil
            friendService = nil
            pushRegistrar.setUser(uid: nil)
            phase = .signedOut
            return
        }
        await loadProfile(uid: uid)
    }

    private func loadProfile(uid: String) async {
        do {
            let snap = try await Firestore.firestore().document("users/\(uid)").getDocument()
            guard snap.exists, let username = snap.get("usernameLower") as? String else {
                phase = .needsUsername
                return
            }
            let profile = UserProfile(
                id: uid,
                username: username,
                displayName: snap.get("displayName") as? String ?? username,
                beerCount: snap.get("beerCount") as? Int ?? 0,
                createdAt: (snap.get("createdAt") as? Timestamp)?.dateValue() ?? Date()
            )
            becomeReady(profile)
        } catch {
            // Signed in but the profile fetch failed (offline, etc.). Don't force
            // `.needsUsername` — that could double-claim. Surface the error and
            // fall back to signedOut so the user can retry the flow.
            errorMessage = "Couldn't load your profile — check your connection."
            phase = .signedOut
        }
    }

    private func becomeReady(_ profile: UserProfile) {
        beerService = FirebaseBeerService(uid: profile.id, ownerName: profile.displayName)
        friendService = FirebaseFriendService(me: profile)
        phase = .ready(profile)
        // Ask for notification permission only once the user is fully onboarded,
        // then keep users/{uid}/private/push.token fresh.
        pushRegistrar.startRegistration()
        pushRegistrar.setUser(uid: profile.id)
    }
}
