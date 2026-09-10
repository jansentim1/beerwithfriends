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
    /// (to flag `isMine` and expose the join code only for my groups).
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

    func members(of groupId: String) async throws -> [GroupMember] {
        let snapshot = try await db.collection("groups/\(groupId)/members").getDocuments()
        return snapshot.documents.map { doc in
            GroupMember(id: doc.documentID,
                        username: doc.get("username") as? String ?? "?",
                        displayName: doc.get("displayName") as? String ?? (doc.get("username") as? String ?? "?"),
                        joinedAt: (doc.get("joinedAt") as? Timestamp)?.dateValue() ?? Date())
        }.sorted { $0.joinedAt < $1.joinedAt }
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

/// Merges the two listeners; yields only once both have reported.
private final class MergeState: @unchecked Sendable {
    private let lock = NSLock()
    private var _groups: [GroupSummary]?
    private var _mine: Set<String>?
    var groups: [GroupSummary]? { get { lock.withLock { _groups } } set { lock.withLock { _groups = newValue } } }
    var mine: Set<String>? { get { lock.withLock { _mine } } set { lock.withLock { _mine = newValue } } }
    func merged() -> [GroupSummary]? {
        lock.withLock {
            guard let g = _groups, let m = _mine else { return nil }
            return g.map { var s = $0; s.isMine = m.contains($0.id); if !s.isMine { s.code = nil }; return s }
        }
    }
}
