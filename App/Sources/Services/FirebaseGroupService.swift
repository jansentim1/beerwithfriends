import BeerKit
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// Firebase-backed `GroupServicing`. Reads are live Firestore listeners (rules:
/// any signed-in user); all writes go through callables.
final class FirebaseGroupService: GroupServicing, @unchecked Sendable {
    private let uid: String
    private let db = Firestore.firestore()

    init(uid: String) { self.uid = uid }

    /// Two listeners merged: every group (leaderboard) and my membership mirror
    /// (to flag `isMine`).
    func observeGroups() -> AsyncThrowingStream<[GroupSummary], Error> {
        let db = self.db
        let uid = self.uid
        return AsyncThrowingStream { continuation in
            let state = MergeState()
            let groupsReg = db.collection("groups")
                .order(by: "todayCount", descending: true)
                .limit(to: 200)
                .addSnapshotListener { snapshot, error in
                    if let error { continuation.finish(throwing: error); return }
                    guard let snapshot else { return }
                    state.groups = snapshot.documents.compactMap(Self.summary(from:))
                    if let merged = state.merged() { continuation.yield(merged) }
                }
            let mineReg = db.collection("users/\(uid)/groups")
                .addSnapshotListener { snapshot, error in
                    if let error { continuation.finish(throwing: error); return }
                    guard let snapshot else { return }
                    state.mine = Set(snapshot.documents.map(\.documentID))
                    if let merged = state.merged() { continuation.yield(merged) }
                }
            continuation.onTermination = { _ in
                groupsReg.remove()
                mineReg.remove()
            }
        }
    }

    private static func summary(from doc: QueryDocumentSnapshot) -> GroupSummary? {
        let d = doc.data()
        guard let name = d["name"] as? String else { return nil }
        return GroupSummary(
            id: doc.documentID,
            name: name,
            code: d["code"] as? String,
            memberCount: d["memberCount"] as? Int ?? 0,
            todayDate: d["todayDate"] as? String ?? "",
            todayCount: d["todayCount"] as? Int ?? 0,
            totalCount: d["totalCount"] as? Int ?? 0,
            isMine: false
        )
    }

    /// Joined order; the ranking inside the group re-sorts on the counters
    /// (`GroupMemberRanking`), which countDrinkForGroups writes here.
    func members(of groupId: String) async throws -> [GroupMember] {
        let snapshot = try await db.collection("groups/\(groupId)/members").getDocuments()
        return snapshot.documents.map { doc in
            GroupMember(id: doc.documentID,
                        username: doc.get("username") as? String ?? "?",
                        displayName: doc.get("displayName") as? String ?? (doc.get("username") as? String ?? "?"),
                        joinedAt: (doc.get("joinedAt") as? Timestamp)?.dateValue() ?? Date(),
                        todayDate: doc.get("todayDate") as? String ?? "",
                        todayCount: doc.get("todayCount") as? Int ?? 0,
                        totalCount: doc.get("totalCount") as? Int ?? 0)
        }.sorted { $0.joinedAt < $1.joinedAt }
    }

    /// One-shot, like `members(of:)`: the sheet re-reads after it writes or
    /// deletes, which is also how it learns that the server's 60 s cooldown
    /// dropped a note.
    func notes(of groupId: String) async throws -> [GroupNote] {
        let snapshot = try await db.collection("groups/\(groupId)/notes")
            .order(by: "at", descending: true)
            .limit(to: 50)
            .getDocuments()
        let notes = snapshot.documents.compactMap { doc -> GroupNote? in
            guard let uid = doc.get("uid") as? String, let text = doc.get("text") as? String else { return nil }
            return GroupNote(id: doc.documentID,
                             uid: uid,
                             displayName: doc.get("displayName") as? String ?? "Someone",
                             text: text,
                             // `at` is a server timestamp: nil for the moment a
                             // local echo is still unacknowledged.
                             at: (doc.get("at") as? Timestamp)?.dateValue() ?? Date())
        }
        return GroupNote.newestFirst(notes)
    }

    func postNote(groupId: String, text: String, displayName: String) async throws {
        // serverTimestamp() is not a nicety: the rules demand `at == request.time`,
        // which is what makes the server-side cooldown unfakeable.
        _ = try await db.collection("groups/\(groupId)/notes").addDocument(data: [
            "uid": uid,
            "displayName": String(displayName.prefix(60)),
            "text": text,
            "at": FieldValue.serverTimestamp(),
        ])
    }

    func deleteNote(groupId: String, noteId: String) async throws {
        try await db.document("groups/\(groupId)/notes/\(noteId)").delete()
    }

    func create(name: String) async throws -> GroupSummary {
        let result = try await call("createGroup", ["name": name])
        return GroupSummary(id: result["id"] as? String ?? "", name: result["name"] as? String ?? name,
                            code: result["code"] as? String, memberCount: 1,
                            todayDate: GroupDay.today(), todayCount: 0, totalCount: 0, isMine: true)
    }

    func join(code: String) async throws -> GroupSummary {
        let result = try await call("joinGroup", ["code": code])
        return GroupSummary(id: result["id"] as? String ?? "", name: result["name"] as? String ?? "",
                            code: result["code"] as? String, memberCount: 0,
                            todayDate: GroupDay.today(), todayCount: 0, totalCount: 0, isMine: true)
    }

    func leave(groupId: String) async throws {
        _ = try await call("leaveGroup", ["groupId": groupId])
    }

    private func call(_ name: String, _ data: [String: Any]) async throws -> [String: Any] {
        do {
            let result = try await EmulatorConfig.functions(region: "europe-west4").httpsCallable(name).call(data)
            return result.data as? [String: Any] ?? [:]
        } catch {
            let nsError = error as NSError
            if nsError.domain == FunctionsErrorDomain,
               let details = nsError.userInfo[FunctionsErrorDetailsKey] as? [String: Any],
               let code = details["code"] as? String {
                switch code {
                case "NOT_FOUND": throw GroupError.notFound
                case "FULL": throw GroupError.full
                case "ALREADY_MEMBER": throw GroupError.alreadyMember
                case "INVALID_NAME": throw GroupError.invalidName
                case "NOT_MEMBER": throw GroupError.notMember
                default: break
                }
            }
            throw error
        }
    }
}

/// Merges the two listeners; yields only once both have reported. The join code
/// rides along on every group, mine or not: `groups/{id}` is readable by any
/// signed-in user (code included), so dropping it client-side protected nothing
/// and only broke one-tap join. What stays members-only is *showing* the code —
/// the invite section in the detail sheet is gated on `isMine`.
private final class MergeState: @unchecked Sendable {
    private let lock = NSLock()
    private var _groups: [GroupSummary]?
    private var _mine: Set<String>?
    var groups: [GroupSummary]? { get { lock.withLock { _groups } } set { lock.withLock { _groups = newValue } } }
    var mine: Set<String>? { get { lock.withLock { _mine } } set { lock.withLock { _mine = newValue } } }
    func merged() -> [GroupSummary]? {
        lock.withLock {
            guard let g = _groups, let m = _mine else { return nil }
            return g.map { var s = $0; s.isMine = m.contains($0.id); return s }
        }
    }
}
