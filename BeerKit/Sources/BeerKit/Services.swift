import Foundation

public enum PhotoFetchError: Error, Equatable { case alreadyViewed, expired, notFriends, notFound }

public enum UsernameClaimError: Error, Equatable { case taken, tooSoon }

/// Server rejected the cheers because it already exists (rules: cheers docs are
/// create-only). The UI keeps the beer marked as cheersed.
public enum CheersError: Error, Equatable { case alreadyCheersed }

/// `deleteAccount` contract: `.retryDelete` means the server erased all data but
/// failed to delete the auth user; the client retries, then signs out locally.
public enum AccountDeletionError: Error, Equatable { case retryDelete }

public protocol BeerServicing: Sendable {
    /// Instant, local: a fresh id + timestamps for an optimistic feed row. Nothing is
    /// written until `logBeer(_:photoJPEG:)`.
    func newBeerLog(hasPhoto: Bool, drink: DrinkKind) -> BeerLog
    /// Persists `beer` (uploading `photoJPEG` first when present). Returns once the
    /// server accepted the write; the caller has already shown the row.
    func logBeer(_ beer: BeerLog, photoJPEG: Data?) async throws
    /// Implementations must tie listener teardown to `continuation.onTermination` —
    /// `for await` cancellation alone does not cancel an underlying Firestore registration.
    func observeFeed() -> AsyncThrowingStream<[BeerLog], Error>
    func cheers(beerId: String) async throws
    /// Quick reply on a mate's beer (create-once per user, like cheers).
    func reply(beerId: String, kind: ReplyKind) async throws
    func fetchPhotoOnce(beerId: String) async throws -> URL
    func viewedBeerIds() async throws -> Set<String>
    /// Which of `beerIds` the current user has already cheersed (survives relaunch).
    func cheersedBeerIds(among beerIds: [String]) async throws -> Set<String>
}

public protocol AuthServicing: Sendable {
    var currentUid: String? { get }
    func signInWithApple(idToken: String, nonce: String) async throws -> String  // returns uid
    func claimUsername(_ username: String, displayName: String) async throws -> UserProfile
    /// Renames an existing account (server callable; once per day). Throws
    /// `UsernameClaimError.taken` when the name is in use, `.tooSoon` when rate-limited.
    func changeUsername(to username: String) async throws -> UserProfile
    /// Renames the nickname (server callable; no cooldown). `displayName` must
    /// already be normalized (`DisplayName.normalize`).
    func changeDisplayName(to displayName: String) async throws -> UserProfile
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

/// Opt-in location: resolves the current spot to a short human name ("Café De Zon",
/// "Amsterdam"), or nil when disabled, denied, or not found in time. Must never
/// take longer than a few seconds; the beer is logged either way.
public struct PlaceResult: Equatable, Sendable {
    public var name: String
    public var coordinate: Coordinate?
    public init(name: String, coordinate: Coordinate? = nil) { self.name = name; self.coordinate = coordinate }
}

public protocol PlaceProviding: Sendable {
    /// The named place (bar or city) and its coordinate, or nil.
    func currentPlace() async -> PlaceResult?
}
