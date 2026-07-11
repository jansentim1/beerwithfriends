import Foundation

public enum PhotoFetchError: Error, Equatable { case alreadyViewed, expired, notFriends, notFound }

public enum UsernameClaimError: Error, Equatable { case taken }

public protocol BeerServicing: Sendable {
    func logBeer(photoJPEG: Data?) async throws -> BeerLog
    /// Implementations must tie listener teardown to `continuation.onTermination` —
    /// `for await` cancellation alone does not cancel an underlying Firestore registration.
    func observeFeed() -> AsyncThrowingStream<[BeerLog], Error>
    func cheers(beerId: String) async throws
    func fetchPhotoOnce(beerId: String) async throws -> URL
    func viewedBeerIds() async throws -> Set<String>
}

public protocol AuthServicing: Sendable {
    var currentUid: String? { get }
    func signInWithApple(idToken: String, nonce: String) async throws -> String  // returns uid
    func claimUsername(_ username: String, displayName: String) async throws -> UserProfile
    func deleteAccount() async throws
    func signOut() throws
}

public protocol FriendServicing: Sendable {
    func searchUser(username: String) async throws -> UserProfile?
    func sendRequest(to uid: String) async throws
    func incomingRequests() async throws -> [FriendRequest]
    func accept(_ request: FriendRequest) async throws
    func decline(_ request: FriendRequest) async throws
    func friends() async throws -> [UserProfile]
    func removeFriend(uid: String) async throws
    func block(uid: String) async throws
    func report(beerId: String?, uid: String, reason: String) async throws
}
