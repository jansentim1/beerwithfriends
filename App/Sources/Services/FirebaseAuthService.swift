import BeerKit
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import Foundation

// COMPILE-PARKED (Task 9): no Xcode on this machine — written against
// Firebase iOS SDK 11 + BeerKit protocol signatures, not yet compiled.

/// Firebase-backed `AuthServicing`. Firebase's singletons are internally
/// thread-safe, hence `@unchecked Sendable`.
final class FirebaseAuthService: AuthServicing, @unchecked Sendable {
    enum ServiceError: Error { case notSignedIn }

    var currentUid: String? { Auth.auth().currentUser?.uid }

    func signInWithApple(idToken: String, nonce: String) async throws -> String {
        let credential = OAuthProvider.appleCredential(
            withIDToken: idToken, rawNonce: nonce, fullName: nil)
        let result = try await Auth.auth().signIn(with: credential)
        return result.user.uid
    }

    /// Batched write of `usernames/{name}` + `users/{uid}` so the rules'
    /// create-once reservation makes the pair atomic. `username` must already
    /// be normalized (see `Username.normalize`); AppState normalizes.
    /// Rules reject a taken name (or a second claim) with permission-denied,
    /// which surfaces as `UsernameClaimError.taken`.
    func claimUsername(_ username: String, displayName: String) async throws -> UserProfile {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw ServiceError.notSignedIn
        }
        let db = Firestore.firestore()
        let batch = db.batch()
        batch.setData(["uid": uid], forDocument: db.document("usernames/\(username)"))
        batch.setData([
            "usernameLower": username,
            "displayName": displayName,
            "beerCount": 0,
            "createdAt": FieldValue.serverTimestamp(),
        ], forDocument: db.document("users/\(uid)"))
        do {
            try await batch.commit()
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw UsernameClaimError.taken
            }
            throw error
        }
        // Server timestamp isn't known locally yet; "now" is close enough for UI.
        return UserProfile(id: uid, username: username, displayName: displayName,
                           beerCount: 0, createdAt: Date())
    }

    /// The `deleteAccount` callable (Task 7) erases Firestore data + photos,
    /// then deletes the auth user (idempotent retry server-side).
    func deleteAccount() async throws {
        do {
            _ = try await Functions.functions(region: "europe-west4").httpsCallable("deleteAccount").call([:])
        } catch {
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain, nsError.localizedDescription.contains("RETRY_DELETE") {
                throw AccountDeletionError.retryDelete
            }
            throw error
        }
        // Auth user is gone server-side; clear local session state too.
        try? Auth.auth().signOut()
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }
}
