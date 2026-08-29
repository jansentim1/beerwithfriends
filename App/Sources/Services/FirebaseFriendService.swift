import BeerKit
import FirebaseFirestore
import Foundation

// COMPILE-PARKED (Task 9): no Xcode on this machine — written against
// Firebase iOS SDK 11 + BeerKit protocol signatures, not yet compiled.

/// Firebase-backed `FriendServicing` for one signed-in user (`me`).
/// Recreated by AppState whenever `phase` becomes `.ready`.
final class FirebaseFriendService: FriendServicing, @unchecked Sendable {
    private let me: UserProfile
    private let db = Firestore.firestore()

    init(me: UserProfile) {
        self.me = me
    }

    // MARK: - Search

    func searchUser(username: String) async throws -> UserProfile? {
        guard let name = Username.normalize(username) else { return nil }
        let reservation = try await db.document("usernames/\(name)").getDocument()
        guard let uid = reservation.get("uid") as? String else { return nil }
        return try await profile(uid: uid)
    }

    private func profile(uid: String) async throws -> UserProfile? {
        let snap = try await db.document("users/\(uid)").getDocument()
        guard snap.exists, let username = snap.get("usernameLower") as? String else { return nil }
        return UserProfile(
            id: uid,
            username: username,
            displayName: snap.get("displayName") as? String ?? username,
            beerCount: snap.get("beerCount") as? Int ?? 0,
            createdAt: (snap.get("createdAt") as? Timestamp)?.dateValue() ?? Date()
        )
    }

    // MARK: - Requests

    /// Schema pinned by rules: `friendRequests/{toUid}/incoming/{me}` = exactly
    /// `{fromUid, fromUsername, fromDisplayName, sentAt}`, strings ≤ 60 chars.
    func sendRequest(to uid: String) async throws {
        try await db.document("friendRequests/\(uid)/incoming/\(me.id)").setData([
            "fromUid": me.id,
            "fromUsername": String(me.username.prefix(60)),
            "fromDisplayName": String(me.displayName.prefix(60)),
            "sentAt": Timestamp(date: Date()),
        ])
    }

    func incomingRequests() async throws -> [FriendRequest] {
        let snapshot = try await db.collection("friendRequests/\(me.id)/incoming").getDocuments()
        return snapshot.documents.compactMap { doc -> FriendRequest? in
            guard let fromUsername = doc.get("fromUsername") as? String,
                  let fromDisplayName = doc.get("fromDisplayName") as? String,
                  let sentAt = doc.get("sentAt") as? Timestamp
            else { return nil }
            return FriendRequest(id: doc.documentID, // sender uid
                                 fromUsername: fromUsername,
                                 fromDisplayName: fromDisplayName,
                                 sentAt: sentAt.dateValue())
        }
        .sorted { $0.sentAt > $1.sentAt }
    }

    /// Accept = recipient materializes their own edge (allowed by rules because
    /// the incoming request exists). The `onFriendAccepted` trigger mirrors the
    /// reverse edge and deletes the request.
    func accept(_ request: FriendRequest) async throws {
        try await db.document("friendships/\(me.id)/friends/\(request.id)")
            .setData(["since": Timestamp(date: Date())])
    }

    func decline(_ request: FriendRequest) async throws {
        try await db.document("friendRequests/\(me.id)/incoming/\(request.id)").delete()
    }

    // MARK: - Friends

    func friends() async throws -> [UserProfile] {
        let snapshot = try await db.collection("friendships/\(me.id)/friends").getDocuments()
        let uids = snapshot.documents.map(\.documentID)
        return try await withThrowingTaskGroup(of: UserProfile?.self) { group in
            for uid in uids {
                group.addTask { try await self.profile(uid: uid) }
            }
            var result: [UserProfile] = []
            for try await profile in group {
                if let profile { result.append(profile) }
            }
            return result.sorted { $0.username < $1.username }
        }
    }

    /// Rules let either endpoint delete either edge, so remove both sides here
    /// (there is no server trigger for plain unfriending).
    func removeFriend(uid: String) async throws {
        let batch = db.batch()
        batch.deleteDocument(db.document("friendships/\(me.id)/friends/\(uid)"))
        batch.deleteDocument(db.document("friendships/\(uid)/friends/\(me.id)"))
        try await batch.commit()
    }

    // MARK: - Safety

    /// ONLY writes the block doc. The `onBlockCreated` trigger severs the
    /// friendship edges and pending requests in both directions server-side.
    func block(uid: String) async throws {
        try await db.document("blocks/\(me.id)/blocked/\(uid)")
            .setData(["at": Timestamp(date: Date())])
    }

    /// Rules require `reporterUid == me` on create; reports are write-only
    /// for clients (reviewed via console/admin).
    func report(beerId: String?, uid: String, reason: String) async throws {
        var data: [String: Any] = [
            "reporterUid": me.id,
            "reportedUid": uid,
            "reason": String(reason.prefix(500)),
            "at": Timestamp(date: Date()),
        ]
        if let beerId { data["beerId"] = beerId }
        _ = try await db.collection("reports").addDocument(data: data)
    }
}

// MARK: - Blocked-user management (Task 10 — beyond the frozen FriendServicing protocol)

/// A row in Settings' blocked-users list. `username` is nil when the blocked
/// account no longer exists.
struct BlockedUser: Identifiable, Equatable, Sendable {
    let id: String // blocked uid
    let username: String?
}

/// `FriendServicing` is frozen in BeerKit (no unblock / blocked-list methods),
/// so these live on the concrete type only; SettingsView reaches them by
/// downcasting `AppState.friendService`. Same file → access to `me`/`db`.
extension FirebaseFriendService {
    /// Reads `blocks/{me}/blocked` (rules: owner-only) and resolves usernames
    /// via public profile gets.
    func blockedUsers() async throws -> [BlockedUser] {
        let snapshot = try await db.collection("blocks/\(me.id)/blocked").getDocuments()
        let uids = snapshot.documents.map(\.documentID)
        return await withTaskGroup(of: BlockedUser.self) { group in
            for uid in uids {
                group.addTask {
                    // Best effort — a deleted account still shows as blocked.
                    BlockedUser(id: uid, username: (try? await self.profile(uid: uid))?.username)
                }
            }
            var result: [BlockedUser] = []
            for await blocked in group {
                result.append(blocked)
            }
            return result.sorted { ($0.username ?? "~") < ($1.username ?? "~") }
        }
    }

    /// Deletes my block doc (rules: owner delete). Unblocking does NOT restore
    /// the severed friendship — either side must send a fresh request.
    func unblock(uid: String) async throws {
        try await db.document("blocks/\(me.id)/blocked/\(uid)").delete()
    }
}
