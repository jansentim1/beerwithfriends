import BeerKit
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

// COMPILE-PARKED (Task 9): no Xcode on this machine — written against
// Firebase iOS SDK 11 + BeerKit protocol signatures, not yet compiled.

/// Firebase-backed `BeerServicing` for one signed-in user. Recreated by
/// AppState whenever `phase` becomes `.ready`.
final class FirebaseBeerService: BeerServicing, @unchecked Sendable {
    private let uid: String
    private let ownerName: String
    private let db = Firestore.firestore()

    /// Rules `in`-query get() budget: chunk owner uids by 10 (NOT the SDK's 30).
    private static let ownerChunkSize = 10

    init(uid: String, ownerName: String) {
        self.uid = uid
        self.ownerName = ownerName
    }

    // MARK: - Log a beer

    /// Photo (if any) is uploaded to `photos/{beerId}.jpg` BEFORE the doc is
    /// created, so `getPhotoOnce` never signs a URL for a missing object.
    /// Doc schema is pinned by the rules: exactly the seven keys below,
    /// `createdAt == request.time` (hence serverTimestamp) and
    /// `expiresAt` within (now, now + 25h] (hence client-computed now + 24h).
    func logBeer(photoJPEG: Data?) async throws -> BeerLog {
        let beerId = UUID().uuidString.lowercased()
        let hasPhoto = photoJPEG != nil
        let photoPath = hasPhoto ? "photos/\(beerId).jpg" : ""

        if let photoJPEG {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await Storage.storage().reference(withPath: photoPath)
                .putDataAsync(photoJPEG, metadata: metadata)
        }

        let now = Date()
        let expiresAt = BeerLog.expiry(from: now)
        try await db.document("beers/\(beerId)").setData([
            "ownerUid": uid,
            "ownerName": String(ownerName.prefix(60)),
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: expiresAt),
            "hasPhoto": hasPhoto,
            "photoPath": photoPath,
            "cheersCount": 0,
        ])

        // Best effort — a failed counter bump must not fail the logged beer.
        try? await db.document("users/\(uid)")
            .updateData(["beerCount": FieldValue.increment(Int64(1))])

        return BeerLog(id: beerId, ownerUid: uid, ownerName: ownerName,
                       createdAt: now, expiresAt: expiresAt,
                       hasPhoto: hasPhoto, cheersCount: 0)
    }

    // MARK: - Feed

    /// Snapshot listeners on `beers` where `ownerUid in` (me + friends, chunked
    /// by 10) and `expiresAt > now`; chunk snapshots are merged into one array.
    /// Listener removal is tied to `continuation.onTermination` — `for await`
    /// cancellation alone does not remove a Firestore registration.
    func observeFeed() -> AsyncThrowingStream<[BeerLog], Error> {
        let db = self.db
        let uid = self.uid
        return AsyncThrowingStream { continuation in
            let listeners = ListenerBag()
            continuation.onTermination = { _ in listeners.cancelAll() }

            let setup = Task {
                do {
                    let friendsSnap = try await db
                        .collection("friendships/\(uid)/friends").getDocuments()
                    var owners = friendsSnap.documents.map(\.documentID)
                    owners.insert(uid, at: 0)
                    let chunks = stride(from: 0, to: owners.count, by: Self.ownerChunkSize)
                        .map { Array(owners[$0..<min($0 + Self.ownerChunkSize, owners.count)]) }

                    let merger = FeedMerger(chunkCount: chunks.count)
                    let now = Timestamp(date: Date())
                    for (index, chunk) in chunks.enumerated() {
                        let registration = db.collection("beers")
                            .whereField("ownerUid", in: chunk)
                            .whereField("expiresAt", isGreaterThan: now)
                            .addSnapshotListener { snapshot, error in
                                if let error {
                                    listeners.cancelAll()
                                    continuation.finish(throwing: error)
                                    return
                                }
                                guard let snapshot else { return }
                                let logs = snapshot.documents.compactMap(Self.beerLog(from:))
                                if let merged = merger.update(chunk: index, logs: logs) {
                                    continuation.yield(merged)
                                }
                            }
                        listeners.add(registration)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            _ = setup // Listener setup is fire-and-forget; teardown is via the bag.
        }
    }

    private static func beerLog(from document: QueryDocumentSnapshot) -> BeerLog? {
        let data = document.data()
        guard let ownerUid = data["ownerUid"] as? String,
              let ownerName = data["ownerName"] as? String,
              let createdAt = data["createdAt"] as? Timestamp,
              let expiresAt = data["expiresAt"] as? Timestamp
        else { return nil }
        return BeerLog(
            id: document.documentID,
            ownerUid: ownerUid,
            ownerName: ownerName,
            createdAt: createdAt.dateValue(),
            expiresAt: expiresAt.dateValue(),
            hasPhoto: data["hasPhoto"] as? Bool ?? false,
            cheersCount: data["cheersCount"] as? Int ?? 0
        )
    }

    // MARK: - Cheers

    /// Schema pinned by rules: `beers/{beerId}/cheers/{me}` = exactly `{uid, at}`.
    func cheers(beerId: String) async throws {
        try await db.document("beers/\(beerId)/cheers/\(uid)").setData([
            "uid": uid,
            "at": Timestamp(date: Date()),
        ])
    }

    // MARK: - View-once photo

    /// Calls the `getPhotoOnce` callable. The function puts the machine code in
    /// `details.code` (the message is human copy) — map from there ONLY.
    func fetchPhotoOnce(beerId: String) async throws -> URL {
        do {
            let result = try await Functions.functions()
                .httpsCallable("getPhotoOnce").call(["beerId": beerId])
            guard let payload = result.data as? [String: Any],
                  let urlString = payload["url"] as? String,
                  let url = URL(string: urlString)
            else { throw PhotoFetchError.notFound }
            return url
        } catch let error as PhotoFetchError {
            throw error
        } catch {
            throw Self.mapCallableError(error)
        }
    }

    private static func mapCallableError(_ error: Error) -> Error {
        let nsError = error as NSError
        guard nsError.domain == FunctionsErrorDomain,
              let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
              let code = details["code"] as? String
        else { return error } // network / auth / unknown — pass through untouched
        switch code {
        case "ALREADY_VIEWED": return PhotoFetchError.alreadyViewed
        case "EXPIRED": return PhotoFetchError.expired
        case "NOT_FRIENDS": return PhotoFetchError.notFriends
        default: return PhotoFetchError.notFound // NOT_FOUND, NO_PHOTO, future codes
        }
    }

    // MARK: - Viewed beer ids

    /// Which of the currently visible photo-beers I've already consumed.
    /// Implemented as per-beer `views/{me}` gets (allowed by the rules'
    /// `viewerUid == me()` clause) rather than a collectionGroup("views")
    /// query, which the current rules have no collection-group match for.
    func viewedBeerIds() async throws -> Set<String> {
        let friendsSnap = try await db.collection("friendships/\(uid)/friends").getDocuments()
        let owners = friendsSnap.documents.map(\.documentID) // my own beers need no view state
        guard !owners.isEmpty else { return [] }

        let chunks = stride(from: 0, to: owners.count, by: Self.ownerChunkSize)
            .map { Array(owners[$0..<min($0 + Self.ownerChunkSize, owners.count)]) }
        let now = Timestamp(date: Date())

        var candidateBeerIds: [String] = []
        for chunk in chunks {
            let snapshot = try await db.collection("beers")
                .whereField("ownerUid", in: chunk)
                .whereField("expiresAt", isGreaterThan: now)
                .getDocuments()
            candidateBeerIds.append(contentsOf: snapshot.documents
                .filter { ($0.data()["hasPhoto"] as? Bool) == true }
                .map(\.documentID))
        }

        let db = self.db
        let uid = self.uid
        return try await withThrowingTaskGroup(of: String?.self) { group in
            for beerId in candidateBeerIds {
                group.addTask {
                    let view = try await db.document("beers/\(beerId)/views/\(uid)").getDocument()
                    return view.exists ? beerId : nil
                }
            }
            var viewed = Set<String>()
            for try await beerId in group {
                if let beerId { viewed.insert(beerId) }
            }
            return viewed
        }
    }
}

// MARK: - Helpers

/// Thread-safe holder for Firestore listener registrations whose teardown is
/// driven by `AsyncThrowingStream.Continuation.onTermination` (a @Sendable
/// closure that can fire before/while listeners are still being registered).
private final class ListenerBag: @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [ListenerRegistration] = []
    private var isCancelled = false

    func add(_ registration: ListenerRegistration) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            registration.remove() // stream already torn down — drop immediately
            return
        }
        registrations.append(registration)
        lock.unlock()
    }

    func cancelAll() {
        lock.lock()
        isCancelled = true
        let toRemove = registrations
        registrations = []
        lock.unlock()
        toRemove.forEach { $0.remove() }
    }
}

/// Merges the per-chunk snapshots of the feed query into one array. Holds the
/// first yield until every chunk has reported once, so the feed doesn't flash
/// a partial list on startup.
private final class FeedMerger: @unchecked Sendable {
    private let lock = NSLock()
    private let chunkCount: Int
    private var chunkLogs: [Int: [BeerLog]] = [:]

    init(chunkCount: Int) {
        self.chunkCount = chunkCount
    }

    /// Returns the merged feed, or nil while chunks are still missing.
    func update(chunk: Int, logs: [BeerLog]) -> [BeerLog]? {
        lock.lock()
        defer { lock.unlock() }
        chunkLogs[chunk] = logs
        guard chunkLogs.count == chunkCount else { return nil }
        return (0..<chunkCount).flatMap { chunkLogs[$0] ?? [] }
    }
}
