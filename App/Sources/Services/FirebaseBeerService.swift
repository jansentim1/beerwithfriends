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

    func newBeerLog(hasPhoto: Bool, drink: DrinkKind) -> BeerLog {
        let now = Date()
        return BeerLog(id: UUID().uuidString.lowercased(), ownerUid: uid, ownerName: ownerName,
                       createdAt: now, expiresAt: BeerLog.expiry(from: now), hasPhoto: hasPhoto,
                       drink: drink)
    }

    /// Photo (if any) is uploaded to `photos/{beerId}.jpg` BEFORE the doc is
    /// created, so `getPhotoOnce` never signs a URL for a missing object (beer
    /// docs are immutable, so hasPhoto can't be flipped afterwards). The caller
    /// already shows the optimistic row; this returns on server ack.
    /// Doc schema is pinned by the rules: exactly the seven keys below,
    /// `createdAt == request.time` (hence serverTimestamp) and
    /// `expiresAt` within (now, now + 25h]; the client sends now + 2 h and the server clamps anything longer.
    func logBeer(_ beer: BeerLog, photoJPEG: Data?) async throws {
        let photoPath = beer.hasPhoto ? "photos/\(beer.id).jpg" : ""
        if let photoJPEG, beer.hasPhoto {
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await Storage.storage().reference(withPath: photoPath)
                .putDataAsync(photoJPEG, metadata: metadata)
        }
        var data: [String: Any] = [
            "ownerUid": uid,
            "ownerName": String(ownerName.prefix(60)),
            "createdAt": FieldValue.serverTimestamp(),
            "expiresAt": Timestamp(date: beer.expiresAt),
            "hasPhoto": beer.hasPhoto,
            "photoPath": photoPath,
            "cheersCount": 0,
        ]
        data["drink"] = beer.drink.rawValue
        if let place = beer.place, !place.isEmpty {
            data["place"] = String(place.prefix(BeerLog.placeMaxLength))
            if let c = beer.placeCoordinate {
                data["placeCoordinate"] = GeoPoint(latitude: c.latitude, longitude: c.longitude)
            }
        }
        try await db.document("beers/\(beer.id)").setData(data)
        // Off the tap path and best effort: a failed counter bump must not fail
        // (or slow down) the logged beer.
        let db = self.db
        let uid = self.uid
        Task.detached {
            try? await db.document("users/\(uid)")
                .updateData(["beerCount": FieldValue.increment(Int64(1))])
        }
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
        // Server-maintained mirror of `beers/{id}/replies/{uid}` (uid → kind).
        // Unknown kinds (a newer client, a future kind) are dropped, not guessed.
        let replies = (data["replies"] as? [String: String] ?? [:])
            .compactMapValues { ReplyKind(rawValue: $0) }
        return BeerLog(
            id: document.documentID,
            ownerUid: ownerUid,
            ownerName: ownerName,
            createdAt: createdAt.dateValue(),
            expiresAt: expiresAt.dateValue(),
            hasPhoto: data["hasPhoto"] as? Bool ?? false,
            cheersCount: data["cheersCount"] as? Int ?? 0,
            place: data["place"] as? String,
            replies: replies,
            drink: (data["drink"] as? String).flatMap(DrinkKind.init(rawValue:)) ?? .pils,
            placeCoordinate: (data["placeCoordinate"] as? GeoPoint).map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        )
    }

    // MARK: - Cheers

    /// Schema pinned by rules: `beers/{beerId}/cheers/{me}` = exactly `{uid, at}`.
    func cheers(beerId: String) async throws {
        do {
            try await db.document("beers/\(beerId)/cheers/\(uid)").setData([
                "uid": uid,
                "at": Timestamp(date: Date()),
            ])
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                // Cheers docs are create-only: a rejected write means it exists.
                throw CheersError.alreadyCheersed
            }
            throw error
        }
    }

    // MARK: - Quick replies

    /// Schema pinned by rules: `beers/{beerId}/replies/{me}` = exactly
    /// `{uid, kind, at}`, create-only and never on your own beer. The server
    /// (onReplyCreated) mirrors it into `beers/{id}.replies` and pushes the owner.
    func reply(beerId: String, kind: ReplyKind) async throws {
        do {
            try await db.document("beers/\(beerId)/replies/\(uid)").setData([
                "uid": uid,
                "kind": kind.rawValue,
                "at": Timestamp(date: Date()),
            ])
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain,
               nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                // Reply docs are create-only: a rejected write means it exists.
                // (Same signal as cheers, so the view model reuses the case.)
                throw CheersError.alreadyCheersed
            }
            throw error
        }
    }

    /// Per-beer `cheers/{me}` gets (readable via the rules' canReactTo clause).
    func cheersedBeerIds(among beerIds: [String]) async throws -> Set<String> {
        let mine = beerIds
        let db = self.db
        let uid = self.uid
        return try await withThrowingTaskGroup(of: String?.self) { group in
            for beerId in mine {
                group.addTask {
                    let doc = try await db.document("beers/\(beerId)/cheers/\(uid)").getDocument()
                    return doc.exists ? beerId : nil
                }
            }
            var found = Set<String>()
            for try await id in group {
                if let id { found.insert(id) }
            }
            return found
        }
    }

    // MARK: - View-once photo

    /// Calls the `getPhotoOnce` callable. The function puts the machine code in
    /// `details.code` (the message is human copy) — map from there ONLY.
    func fetchPhotoOnce(beerId: String) async throws -> URL {
        do {
            let result = try await EmulatorConfig.functions(region: "europe-west4")
                .httpsCallable("getPhotoOnce").call(["beerId": beerId])
            // The server returns the JPEG bytes (base64), never a reusable URL.
            // Written to a temp file so the viewer can load it like any local image.
            guard let payload = result.data as? [String: Any],
                  let base64 = payload["photo"] as? String,
                  let data = Data(base64Encoded: base64)
            else { throw PhotoFetchError.notFound }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("viewonce-\(beerId).jpg")
            try data.write(to: url, options: [.atomic, .completeFileProtection])
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

    // MARK: - Screenshot receipts (Task 10 — beyond the frozen BeerServicing protocol)

    /// Best-effort screenshot receipt, fired by PhotoViewerView (via a closure
    /// RootView builds from this concrete type — the BeerKit protocols are
    /// frozen, so this method deliberately lives outside `BeerServicing`).
    /// Schema pinned by rules: `beers/{beerId}/screenshots/{me}` = exactly `{uid, at}`.
    func recordScreenshot(beerId: String) async {
        try? await db.document("beers/\(beerId)/screenshots/\(uid)").setData([
            "uid": uid,
            "at": Timestamp(date: Date()),
        ])
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
