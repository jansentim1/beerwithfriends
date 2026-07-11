# BeerWithMe Clone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** iPhone app: tap to log a beer → friends get a push and can cheers back; optional live camera photo each friend can view exactly once (server-enforced), 24h expiry.

**Architecture:** Testable core in a local Swift Package `BeerKit` (models, validation, view models against service protocols) + thin SwiftUI shell with Firebase-backed service implementations. Backend = Firebase: Firestore, Storage, TypeScript Cloud Functions (push fanout, view-once gate `getPhotoOnce`, expiry cleanup, account deletion), locked down by security rules.

**Tech Stack:** Swift 6 / SwiftUI (iOS 17+), Firebase iOS SDK via SPM, XcodeGen; Cloud Functions v2 (TypeScript, Node 20), firebase-admin, vitest, Firebase Emulator Suite (`--project demo-beerwithme`, offline-capable).

Spec: `docs/superpowers/specs/2026-07-11-beerwithme-design.md`

## Global Constraints

- **No Xcode on this Mac.** `swift build/test` (CLT, macOS) is the only Swift gate. The iOS app target compiles only after Tim installs Xcode — app-shell tasks gate on `swift test` staying green + code review, and are marked **compile-parked**.
- **CLT quirks (discovered Task 1):** the Swift gate is `SWIFTPM_CUSTOM_LIBS_DIR="$REPO/tools/swiftpm-libs" swift test` (broken CLT SwiftPM libs; see README). CLT ships no XCTest — all BeerKit tests use **Swift Testing** (`import Testing`, `#expect(a == b)`, `@Test func`, suites are structs) instead of the XCTest code shown in Tasks 2–3; convert mechanically, keep the same assertions. `@MainActor` view-model tests: annotate the test function `@Test @MainActor`.
- Every gate is a command with a boolean/numeric result (Project Dirk rule). No LLM-opinion gates except the explicit reviewer step.
- Firebase emulators must run with `--project demo-beerwithme` (demo prefix = fully offline, no credentials).
- Photos: camera only, JPEG ≤ 5 MB, path `photos/{beerId}.jpg`. View-once enforced ONLY in `getPhotoOnce` (owner exempt). Expiry = createdAt + 24h.
- Usernames: 3–15 chars, `[a-z0-9_]`, must start with a letter, stored lowercase.
- Commit after every task (small, working commits). Never commit `node_modules`, `.build`, or generated Xcode projects.
- App Store v1 must include: report content, block users, in-app account deletion, camera/notification usage strings, 17+ rating.

## Autonomous Loop Protocol

State lives in `STATE.md` (repo root): current task, parked items, blockers for Tim. One loop iteration =

1. Read `STATE.md` + this plan; pick the first unchecked task.
2. Dispatch a fresh implementer subagent with the task text (it sees only its task + Interfaces block).
3. Run the task's gate command(s). Fail → fix (max 3 attempts, then park with notes in `STATE.md`).
4. Dispatch reviewer subagent (code-reviewer) on the diff; apply must-fix findings; re-run gates.
5. Commit, tick the checkbox in this file, update `STATE.md`, schedule next wakeup.

Stop conditions: all tasks done/parked, or a blocker only Tim can clear (install Xcode; create real Firebase project + Apple Developer account). Blockers go in `STATE.md` under "Needs Tim".

---

## Milestone 0 — Scaffold

### Task 1: Repo scaffold (BeerKit package, functions project, gates runnable)

**Files:**
- Create: `.gitignore`, `README.md`, `STATE.md`
- Create: `BeerKit/Package.swift`, `BeerKit/Sources/BeerKit/BeerKit.swift`, `BeerKit/Tests/BeerKitTests/SmokeTests.swift`
- Create: `firebase.json`, `functions/package.json`, `functions/tsconfig.json`, `functions/vitest.config.ts`, `functions/src/index.ts`, `functions/test/smoke.test.ts`
- Create: `project.yml` (XcodeGen spec, compile-parked)

**Interfaces:**
- Produces: gate commands used by every later task — `cd BeerKit && swift test` and `cd functions && npm test`; emulator gate `npx firebase-tools emulators:exec --project demo-beerwithme --only firestore,auth,storage "npm --prefix functions run test:emu"`.

- [x] **Step 1: Write `.gitignore`, `README.md`, `STATE.md`**

`.gitignore`:
```
.build/
node_modules/
*.xcodeproj
firebase-debug.log
firestore-debug.log
ui-debug.log
functions/lib/
.DS_Store
```

`STATE.md`:
```markdown
# Loop state
- Current task: 1 (scaffold)
- Done: —
- Parked: —
- Needs Tim: install Xcode (App Store); later: real Firebase project (Blaze) + Apple Developer account.
```

`README.md`: one paragraph describing the app + how to run gates (copy the two gate commands from Interfaces above).

- [x] **Step 2: BeerKit package with a failing smoke test**

`BeerKit/Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "BeerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BeerKit", targets: ["BeerKit"])],
    targets: [
        .target(name: "BeerKit"),
        .testTarget(name: "BeerKitTests", dependencies: ["BeerKit"]),
    ]
)
```

`BeerKit/Sources/BeerKit/BeerKit.swift`:
```swift
public enum BeerKitInfo {
    public static let version = "0.1.0"
}
```

`BeerKit/Tests/BeerKitTests/SmokeTests.swift`:
```swift
import XCTest
@testable import BeerKit

final class SmokeTests: XCTestCase {
    func testVersion() { XCTAssertEqual(BeerKitInfo.version, "0.1.0") }
}
```

- [x] **Step 3: Run `cd BeerKit && swift test`** — Expected: PASS (1 test).

- [x] **Step 4: Functions scaffold**

`functions/package.json`:
```json
{
  "name": "beerwithme-functions",
  "private": true,
  "engines": { "node": "20" },
  "main": "lib/index.js",
  "scripts": {
    "build": "tsc",
    "test": "vitest run --exclude 'test/emu/**'",
    "test:emu": "vitest run test/emu"
  },
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^5.0.0"
  },
  "devDependencies": {
    "typescript": "^5.4.0",
    "vitest": "^1.6.0"
  }
}
```

`functions/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022", "module": "NodeNext", "moduleResolution": "NodeNext",
    "outDir": "lib", "strict": true, "esModuleInterop": true, "skipLibCheck": true,
    "sourceMap": true
  },
  "include": ["src"]
}
```

`functions/vitest.config.ts`:
```ts
import { defineConfig } from "vitest/config";
export default defineConfig({ test: { testTimeout: 20000, hookTimeout: 30000 } });
```

`functions/src/index.ts`:
```ts
export const PLACEHOLDER_REMOVED_IN_TASK_5 = true; // real exports land in Tasks 5–7
```

`functions/test/smoke.test.ts`:
```ts
import { describe, it, expect } from "vitest";
describe("scaffold", () => { it("runs", () => expect(1 + 1).toBe(2)); });
```

`firebase.json`:
```json
{
  "functions": { "source": "functions" },
  "firestore": { "rules": "firestore.rules" },
  "storage": { "rules": "storage.rules" },
  "emulators": {
    "auth": { "port": 9099 },
    "firestore": { "port": 8080 },
    "storage": { "port": 9199 },
    "ui": { "enabled": false }
  }
}
```

Also create placeholder-permissive `firestore.rules` / `storage.rules` (locked down in Task 8):
```
rules_version = '2';
service cloud.firestore { match /databases/{db}/documents { match /{doc=**} { allow read, write: if request.auth != null; } } }
```
```
rules_version = '2';
service firebase.storage { match /b/{bucket}/o { match /{all=**} { allow read, write: if request.auth != null; } } }
```

- [x] **Step 5: Run `cd functions && npm install && npm test`** — Expected: PASS (1 test).

- [x] **Step 6: XcodeGen spec (compile-parked)**

`project.yml`:
```yaml
name: BeerWithMe
options: { bundleIdPrefix: com.timjansen, deploymentTarget: { iOS: "17.0" } }
packages:
  BeerKit: { path: BeerKit }
  Firebase: { url: https://github.com/firebase/firebase-ios-sdk, from: 11.0.0 }
targets:
  BeerWithMe:
    type: application
    platform: iOS
    sources: [App/Sources]
    dependencies:
      - package: BeerKit
      - package: Firebase
        products: [FirebaseAuth, FirebaseFirestore, FirebaseStorage, FirebaseMessaging, FirebaseFunctions]
    info:
      path: App/Info.plist
      properties:
        NSCameraUsageDescription: "Take a live photo of your beer to share with friends."
        UIBackgroundModes: [remote-notification]
```

- [x] **Step 7: Commit** — `git add -A && git commit -m "chore: scaffold BeerKit, functions, emulator config"`

---

## Milestone 1 — BeerKit core

### Task 2: Username validation + domain models

**Files:**
- Create: `BeerKit/Sources/BeerKit/Username.swift`, `BeerKit/Sources/BeerKit/Models.swift`
- Test: `BeerKit/Tests/BeerKitTests/UsernameTests.swift`, `BeerKit/Tests/BeerKitTests/ModelTests.swift`

**Interfaces:**
- Produces: `Username.normalize(_ raw: String) -> String?`; `UserProfile`, `BeerLog`, `FriendRequest` structs (Codable, Equatable, Identifiable, Sendable) with the exact fields below. Later tasks (3, 9, 10) consume these verbatim.

- [x] **Step 1: Write failing tests**

`UsernameTests.swift`:
```swift
import XCTest
@testable import BeerKit

final class UsernameTests: XCTestCase {
    func testValidLowercases() { XCTAssertEqual(Username.normalize("TimJansen"), "timjansen") }
    func testTrimsWhitespace() { XCTAssertEqual(Username.normalize("  tim_1 "), "tim_1") }
    func testTooShort() { XCTAssertNil(Username.normalize("ab")) }
    func testTooLong() { XCTAssertNil(Username.normalize(String(repeating: "a", count: 16))) }
    func testMustStartWithLetter() { XCTAssertNil(Username.normalize("1tim")); XCTAssertNil(Username.normalize("_tim")) }
    func testRejectsSymbolsAndUnicode() { XCTAssertNil(Username.normalize("tim!")); XCTAssertNil(Username.normalize("tïm")) }
}
```

`ModelTests.swift`:
```swift
import XCTest
@testable import BeerKit

final class ModelTests: XCTestCase {
    func testBeerLogRoundTripsJSON() throws {
        let log = BeerLog(id: "b1", ownerUid: "u1", ownerName: "Tim",
                          createdAt: Date(timeIntervalSince1970: 1000),
                          expiresAt: Date(timeIntervalSince1970: 1000 + 86400),
                          hasPhoto: true, cheersCount: 2)
        let data = try JSONEncoder().encode(log)
        XCTAssertEqual(try JSONDecoder().decode(BeerLog.self, from: data), log)
    }
    func testExpiryIs24h() {
        let created = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(BeerLog.expiry(from: created), created.addingTimeInterval(24 * 3600))
    }
}
```

- [x] **Step 2: Run `cd BeerKit && swift test`** — Expected: FAIL (Username/BeerLog undefined).

- [x] **Step 3: Implement**

`Username.swift`:
```swift
import Foundation

public enum Username {
    /// Lowercased valid username or nil. Rules: 3–15 chars, [a-z0-9_], starts with a letter.
    public static func normalize(_ raw: String) -> String? {
        let c = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard (3...15).contains(c.count),
              let first = c.first, first.isASCII, first.isLetter,
              c.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_" })
        else { return nil }
        return c
    }
}
```

`Models.swift`:
```swift
import Foundation

public struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: String            // Firebase uid
    public var username: String      // normalized lowercase
    public var displayName: String
    public var beerCount: Int
    public var createdAt: Date
    public init(id: String, username: String, displayName: String, beerCount: Int = 0, createdAt: Date) {
        self.id = id; self.username = username; self.displayName = displayName
        self.beerCount = beerCount; self.createdAt = createdAt
    }
}

public struct BeerLog: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var ownerUid: String
    public var ownerName: String
    public var createdAt: Date
    public var expiresAt: Date
    public var hasPhoto: Bool
    public var cheersCount: Int
    public init(id: String, ownerUid: String, ownerName: String, createdAt: Date,
                expiresAt: Date, hasPhoto: Bool, cheersCount: Int = 0) {
        self.id = id; self.ownerUid = ownerUid; self.ownerName = ownerName
        self.createdAt = createdAt; self.expiresAt = expiresAt
        self.hasPhoto = hasPhoto; self.cheersCount = cheersCount
    }
    public static func expiry(from createdAt: Date) -> Date { createdAt.addingTimeInterval(24 * 3600) }
}

public struct FriendRequest: Codable, Equatable, Identifiable, Sendable {
    public var id: String            // sender uid
    public var fromUsername: String
    public var fromDisplayName: String
    public var sentAt: Date
    public init(id: String, fromUsername: String, fromDisplayName: String, sentAt: Date) {
        self.id = id; self.fromUsername = fromUsername
        self.fromDisplayName = fromDisplayName; self.sentAt = sentAt
    }
}
```

- [x] **Step 4: Run `cd BeerKit && swift test`** — Expected: PASS (all).
- [x] **Step 5: Commit** — `git commit -am "feat(beerkit): username validation + domain models"`

### Task 3: Photo chip state, service protocols, HomeViewModel

**Files:**
- Create: `BeerKit/Sources/BeerKit/PhotoChipState.swift`, `BeerKit/Sources/BeerKit/Services.swift`, `BeerKit/Sources/BeerKit/HomeViewModel.swift`
- Test: `BeerKit/Tests/BeerKitTests/PhotoChipStateTests.swift`, `BeerKit/Tests/BeerKitTests/HomeViewModelTests.swift`

**Interfaces:**
- Consumes: `BeerLog` from Task 2.
- Produces (Tasks 9–10 implement/consume these exact signatures):
  - `enum PhotoChipState { case none, sealed, seen, expired }`; `BeerLog.photoChipState(viewedByMe:now:) -> PhotoChipState`
  - `protocol BeerServicing: Sendable { func logBeer(photoJPEG: Data?) async throws -> BeerLog; func observeFeed() -> AsyncThrowingStream<[BeerLog], Error>; func cheers(beerId: String) async throws; func fetchPhotoOnce(beerId: String) async throws -> URL; func viewedBeerIds() async throws -> Set<String> }`
  - `enum PhotoFetchError: Error { case alreadyViewed, expired, notFriends, notFound }`
  - `@MainActor final class HomeViewModel: ObservableObject` — `init(service:now:)`, `feed`, `viewedBeerIds`, `errorMessage`, `func start() async`, `func logBeer(photoJPEG: Data?) async`, `func cheers(_ beer: BeerLog) async`, `func openPhoto(_ beer: BeerLog) async -> URL?`

- [x] **Step 1: Write failing tests**

`PhotoChipStateTests.swift`:
```swift
import XCTest
@testable import BeerKit

final class PhotoChipStateTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 0)
    func log(hasPhoto: Bool) -> BeerLog {
        BeerLog(id: "b", ownerUid: "u", ownerName: "n", createdAt: t0,
                expiresAt: BeerLog.expiry(from: t0), hasPhoto: hasPhoto)
    }
    func testNoPhoto() { XCTAssertEqual(log(hasPhoto: false).photoChipState(viewedByMe: false, now: t0), .none) }
    func testSealed() { XCTAssertEqual(log(hasPhoto: true).photoChipState(viewedByMe: false, now: t0), .sealed) }
    func testSeen() { XCTAssertEqual(log(hasPhoto: true).photoChipState(viewedByMe: true, now: t0), .seen) }
    func testExpired() {
        let later = t0.addingTimeInterval(24 * 3600)
        XCTAssertEqual(log(hasPhoto: true).photoChipState(viewedByMe: false, now: later), .expired)
    }
}
```

`HomeViewModelTests.swift`:
```swift
import XCTest
@testable import BeerKit

final class FakeBeerService: BeerServicing, @unchecked Sendable {
    var logged: [Data?] = []
    var cheersed: [String] = []
    var photoResult: Result<URL, Error> = .success(URL(string: "https://x.test/p.jpg")!)
    var feedContinuation: AsyncStream<[BeerLog]>.Continuation?
    func logBeer(photoJPEG: Data?) async throws -> BeerLog {
        logged.append(photoJPEG)
        let now = Date(timeIntervalSince1970: 500)
        return BeerLog(id: "new", ownerUid: "me", ownerName: "Me", createdAt: now,
                       expiresAt: BeerLog.expiry(from: now), hasPhoto: photoJPEG != nil)
    }
    func observeFeed() -> AsyncThrowingStream<[BeerLog], Error> {
        AsyncStream { self.feedContinuation = $0 }
    }
    func cheers(beerId: String) async throws { cheersed.append(beerId) }
    func fetchPhotoOnce(beerId: String) async throws -> URL { try photoResult.get() }
    func viewedBeerIds() async throws -> Set<String> { ["seen1"] }
}

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testLogBeerAppendsToFeed() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        await vm.logBeer(photoJPEG: nil)
        XCTAssertEqual(svc.logged.count, 1)
        XCTAssertEqual(vm.feed.first?.id, "new")
    }
    func testOpenPhotoMarksViewed() async {
        let svc = FakeBeerService()
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let t0 = Date(timeIntervalSince1970: 400)
        let beer = BeerLog(id: "b1", ownerUid: "u2", ownerName: "Joost", createdAt: t0,
                           expiresAt: BeerLog.expiry(from: t0), hasPhoto: true)
        let url = await vm.openPhoto(beer)
        XCTAssertNotNil(url)
        XCTAssertTrue(vm.viewedBeerIds.contains("b1"))
    }
    func testOpenPhotoAlreadyViewedSetsError() async {
        let svc = FakeBeerService()
        svc.photoResult = .failure(PhotoFetchError.alreadyViewed)
        let vm = HomeViewModel(service: svc, now: { Date(timeIntervalSince1970: 500) })
        let t0 = Date(timeIntervalSince1970: 400)
        let beer = BeerLog(id: "b1", ownerUid: "u2", ownerName: "Joost", createdAt: t0,
                           expiresAt: BeerLog.expiry(from: t0), hasPhoto: true)
        let url = await vm.openPhoto(beer)
        XCTAssertNil(url)
        XCTAssertNotNil(vm.errorMessage)
    }
}
```

- [x] **Step 2: Run `cd BeerKit && swift test`** — Expected: FAIL (types undefined).

- [x] **Step 3: Implement**

`PhotoChipState.swift`:
```swift
import Foundation

public enum PhotoChipState: Equatable, Sendable { case none, sealed, seen, expired }

public extension BeerLog {
    func photoChipState(viewedByMe: Bool, now: Date) -> PhotoChipState {
        guard hasPhoto else { return .none }
        if now >= expiresAt { return .expired }
        return viewedByMe ? .seen : .sealed
    }
}
```

`Services.swift`:
```swift
import Foundation

public enum PhotoFetchError: Error, Equatable { case alreadyViewed, expired, notFriends, notFound }

public protocol BeerServicing: Sendable {
    func logBeer(photoJPEG: Data?) async throws -> BeerLog
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
```

`HomeViewModel.swift`:
```swift
import Foundation

@MainActor
public final class HomeViewModel: ObservableObject {
    @Published public private(set) var feed: [BeerLog] = []
    @Published public private(set) var viewedBeerIds: Set<String> = []
    @Published public private(set) var isLogging = false
    @Published public var errorMessage: String?

    private let service: any BeerServicing
    private let now: () -> Date

    public init(service: any BeerServicing, now: @escaping () -> Date = { Date() }) {
        self.service = service
        self.now = now
    }

    public func start() async {
        viewedBeerIds = (try? await service.viewedBeerIds()) ?? []
        for await logs in service.observeFeed() {
            let cutoff = now()
            feed = logs.filter { $0.expiresAt > cutoff }.sorted { $0.createdAt > $1.createdAt }
        }
    }

    public func logBeer(photoJPEG: Data?) async {
        guard !isLogging else { return }
        isLogging = true
        defer { isLogging = false }
        do {
            let log = try await service.logBeer(photoJPEG: photoJPEG)
            feed.insert(log, at: 0)
        } catch {
            errorMessage = "Couldn't log your beer — try again."
        }
    }

    public func cheers(_ beer: BeerLog) async {
        if let i = feed.firstIndex(where: { $0.id == beer.id }) { feed[i].cheersCount += 1 }
        try? await service.cheers(beerId: beer.id)
    }

    public func openPhoto(_ beer: BeerLog) async -> URL? {
        do {
            let url = try await service.fetchPhotoOnce(beerId: beer.id)
            viewedBeerIds.insert(beer.id)
            return url
        } catch PhotoFetchError.alreadyViewed {
            viewedBeerIds.insert(beer.id)
            errorMessage = "You already used your one view 👀"
            return nil
        } catch PhotoFetchError.expired {
            errorMessage = "This photo has expired."
            return nil
        } catch {
            errorMessage = "Couldn't open the photo."
            return nil
        }
    }
}
```

- [x] **Step 4: Run `cd BeerKit && swift test`** — Expected: PASS.

**Review outcome (applied post-implementation):** `cheers()` now has a duplicate-tap guard (`cheersedBeerIds`) and rollback + errorMessage on failure; `start()` has a re-entrancy guard and catches feed-stream errors; `observeFeed()` returns `AsyncThrowingStream<[BeerLog], Error>` (implementations MUST tie Firestore listener removal to `continuation.onTermination`); `UsernameClaimError.taken` added for Task 9's `claimUsername`; distinct copy for `PhotoFetchError.notFriends`. Task 9/10 must use these revised signatures.

- [x] **Step 5: Commit** — `git commit -am "feat(beerkit): chip state, service protocols, HomeViewModel"`

---

## Milestone 2 — Cloud Functions

### Task 4: Emulator test harness

**Files:**
- Create: `functions/test/emu/helpers.ts`, `functions/test/emu/harness.test.ts`
- Modify: `README.md` (add emulator gate command)

**Interfaces:**
- Produces: `initTestDb(): Firestore` (admin SDK bound to emulator) and `seedFriends(db, a: string, b: string): Promise<void>` + `seedUser(db, uid, username, fcmToken?)` used by Tasks 5–8.

- [x] **Step 1: Write helpers + a seed round-trip test**

`functions/test/emu/helpers.ts`:
```ts
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, Firestore, Timestamp } from "firebase-admin/firestore";

export function initTestDb(): Firestore {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error("Run inside emulators:exec");
  if (getApps().length === 0) initializeApp({ projectId: "demo-beerwithme" });
  return getFirestore();
}

export async function seedUser(db: Firestore, uid: string, username: string, fcmToken?: string) {
  await db.doc(`users/${uid}`).set({
    usernameLower: username, displayName: username, beerCount: 0,
    createdAt: Timestamp.now(), ...(fcmToken ? { fcmToken } : {}),
  });
  await db.doc(`usernames/${username}`).set({ uid });
}

export async function seedFriends(db: Firestore, a: string, b: string) {
  await db.doc(`friendships/${a}/friends/${b}`).set({ since: Timestamp.now() });
  await db.doc(`friendships/${b}/friends/${a}`).set({ since: Timestamp.now() });
}

export async function clearDb(db: Firestore) {
  const collections = await db.listCollections();
  await Promise.all(collections.map(async (c) => {
    const docs = await c.listDocuments();
    await Promise.all(docs.map((d) => db.recursiveDelete(d)));
  }));
}
```

`functions/test/emu/harness.test.ts`:
```ts
import { describe, it, expect, beforeEach } from "vitest";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";

const db = initTestDb();
beforeEach(() => clearDb(db));

describe("harness", () => {
  it("seeds users and friendships", async () => {
    await seedUser(db, "u1", "tim");
    await seedUser(db, "u2", "joost");
    await seedFriends(db, "u1", "u2");
    expect((await db.doc("users/u1").get()).get("usernameLower")).toBe("tim");
    expect((await db.doc("friendships/u2/friends/u1").get()).exists).toBe(true);
  });
});
```

- [x] **Step 2: Run the emulator gate from repo root** —
`npx firebase-tools emulators:exec --project demo-beerwithme --only firestore,auth,storage "npm --prefix functions run test:emu"`
Expected: PASS. (First run downloads emulator JARs; needs Java — if missing, `brew install openjdk` and park if brew prompts for a password.)
- [x] **Step 3: Commit** — `git commit -am "test(functions): emulator harness"`

### Task 5: `getPhotoOnce` — the view-once gate

**Files:**
- Create: `functions/src/photo.ts`
- Modify: `functions/src/index.ts` (replace placeholder)
- Test: `functions/test/emu/photo.test.ts`

**Interfaces:**
- Consumes: harness from Task 4.
- Produces: `getPhotoOnceCore(db, signedUrl, callerUid, beerId, now?) => Promise<string>`; `PhotoError` with `code: "NOT_FOUND"|"NOT_FRIENDS"|"EXPIRED"|"ALREADY_VIEWED"|"NO_PHOTO"`; callable export `getPhotoOnce` mapping PhotoError → HttpsError (`failed-precondition`, message = code). Task 9's `FirebaseBeerService.fetchPhotoOnce` maps these codes to `PhotoFetchError`.

- [x] **Step 1: Write failing tests**

`functions/test/emu/photo.test.ts`:
```ts
import { describe, it, expect, beforeEach } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";
import { getPhotoOnceCore, PhotoError } from "../../src/photo";

const db = initTestDb();
const url = async (p: string) => `signed://${p}`;
const NOW = new Date("2026-07-11T12:00:00Z");

async function seedBeer(id: string, owner: string, hasPhoto = true, expired = false) {
  const created = expired ? new Date(NOW.getTime() - 25 * 3600_000) : NOW;
  await db.doc(`beers/${id}`).set({
    ownerUid: owner, ownerName: "Owner", hasPhoto,
    photoPath: `photos/${id}.jpg`, cheersCount: 0,
    createdAt: Timestamp.fromDate(created),
    expiresAt: Timestamp.fromDate(new Date(created.getTime() + 24 * 3600_000)),
  });
}

beforeEach(async () => {
  await clearDb(db);
  await seedUser(db, "owner", "tim");
  await seedUser(db, "friend", "joost");
  await seedUser(db, "stranger", "hans");
  await seedFriends(db, "owner", "friend");
});

describe("getPhotoOnceCore", () => {
  it("friend gets URL once, second view rejected", async () => {
    await seedBeer("b1", "owner");
    expect(await getPhotoOnceCore(db, url, "friend", "b1", NOW)).toBe("signed://photos/b1.jpg");
    await expect(getPhotoOnceCore(db, url, "friend", "b1", NOW))
      .rejects.toMatchObject({ code: "ALREADY_VIEWED" });
  });
  it("owner can re-view without consuming", async () => {
    await seedBeer("b1", "owner");
    await getPhotoOnceCore(db, url, "owner", "b1", NOW);
    expect(await getPhotoOnceCore(db, url, "owner", "b1", NOW)).toBe("signed://photos/b1.jpg");
  });
  it("stranger rejected", async () => {
    await seedBeer("b1", "owner");
    await expect(getPhotoOnceCore(db, url, "stranger", "b1", NOW))
      .rejects.toMatchObject({ code: "NOT_FRIENDS" });
  });
  it("expired rejected", async () => {
    await seedBeer("b1", "owner", true, true);
    await expect(getPhotoOnceCore(db, url, "friend", "b1", NOW))
      .rejects.toMatchObject({ code: "EXPIRED" });
  });
  it("missing / photoless rejected", async () => {
    await expect(getPhotoOnceCore(db, url, "friend", "nope", NOW))
      .rejects.toMatchObject({ code: "NOT_FOUND" });
    await seedBeer("b2", "owner", false);
    await expect(getPhotoOnceCore(db, url, "friend", "b2", NOW))
      .rejects.toMatchObject({ code: "NO_PHOTO" });
  });
  it("view record written with timestamp", async () => {
    await seedBeer("b1", "owner");
    await getPhotoOnceCore(db, url, "friend", "b1", NOW);
    const view = await db.doc("beers/b1/views/friend").get();
    expect(view.exists).toBe(true);
  });
});
```

- [x] **Step 2: Run emulator gate** — Expected: FAIL (module missing).

- [x] **Step 3: Implement**

`functions/src/photo.ts`:
```ts
import { Firestore, Timestamp } from "firebase-admin/firestore";

export type SignedUrlProvider = (photoPath: string) => Promise<string>;
export type PhotoErrorCode = "NOT_FOUND" | "NOT_FRIENDS" | "EXPIRED" | "ALREADY_VIEWED" | "NO_PHOTO";

export class PhotoError extends Error {
  constructor(public code: PhotoErrorCode) { super(code); }
}

export async function getPhotoOnceCore(
  db: Firestore, signedUrl: SignedUrlProvider,
  callerUid: string, beerId: string, now: Date = new Date(),
): Promise<string> {
  const beerRef = db.collection("beers").doc(beerId);
  const snap = await beerRef.get();
  if (!snap.exists) throw new PhotoError("NOT_FOUND");
  const beer = snap.data()!;
  if (!beer.hasPhoto) throw new PhotoError("NO_PHOTO");
  if ((beer.expiresAt as Timestamp).toDate() <= now) throw new PhotoError("EXPIRED");

  if (beer.ownerUid !== callerUid) {
    const friend = await db.doc(`friendships/${beer.ownerUid}/friends/${callerUid}`).get();
    if (!friend.exists) throw new PhotoError("NOT_FRIENDS");
    await db.runTransaction(async (tx) => {
      const viewRef = beerRef.collection("views").doc(callerUid);
      if ((await tx.get(viewRef)).exists) throw new PhotoError("ALREADY_VIEWED");
      tx.set(viewRef, { viewedAt: Timestamp.fromDate(now) });
    });
  }
  return signedUrl(beer.photoPath as string);
}
```

`functions/src/index.ts` (replace placeholder):
```ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { getPhotoOnceCore, PhotoError } from "./photo";

initializeApp();

async function signedUrl(photoPath: string): Promise<string> {
  const [url] = await getStorage().bucket().file(photoPath)
    .getSignedUrl({ action: "read", expires: Date.now() + 60_000 });
  return url;
}

export const getPhotoOnce = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required");
  try {
    return { url: await getPhotoOnceCore(getFirestore(), signedUrl, req.auth.uid, req.data.beerId) };
  } catch (e) {
    if (e instanceof PhotoError) throw new HttpsError("failed-precondition", e.code);
    throw e;
  }
});
```

- [x] **Step 4: Run emulator gate + `npm --prefix functions run build`** — Expected: tests PASS, tsc clean.

**Review outcome (applied post-implementation, security review):** `getPhotoOnceCore` now (a) enforces blocks in BOTH directions (`blocks/{owner}/blocked/{caller}` and reverse) — missing spec requirement; (b) decides friendship+blocks+already-viewed atomically INSIDE the view transaction (no TOCTOU); (c) discloses NO_PHOTO/EXPIRED only after authorization passes; (d) validates `beerId` against `^[A-Za-z0-9_-]{1,128}$` and never signs a `photoPath` that isn't exactly `photos/{beerId}.jpg`; (e) stamps `allViewedAt` on the beer doc once every current friend has viewed — **Task 7's `cleanupExpiredCore` must ALSO early-delete photo objects (object only, not the doc) for beers with `allViewedAt` older than ~10 minutes, and Task 7 tests must cover it**. The callable maps errors to proper statuses (`permission-denied` for NOT_FRIENDS, `not-found` for NOT_FOUND/NO_PHOTO, `failed-precondition` for EXPIRED/ALREADY_VIEWED) with the machine code in `details.code` — **Task 9's `fetchPhotoOnce` must read `details.code`, not the message**. 12 emulator tests.

- [x] **Step 5: Commit** — `git commit -am "feat(functions): getPhotoOnce view-once gate"`

### Task 6: Push fanout (`onBeerCreated`, `onCheersCreated`)

**Files:**
- Create: `functions/src/pushes.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/test/emu/pushes.test.ts`

**Interfaces:**
- Consumes: harness (Task 4).
- Produces: `fanoutBeerCreated(db, push, beerId, beer)` and `notifyCheers(db, push, beerOwnerUid, cheererUid)` with `type Pusher = (tokens: string[], title: string, body: string, data: Record<string, string>) => Promise<void>`; Firestore triggers `onBeerCreated` (`beers/{beerId}`), `onCheersCreated` (`beers/{beerId}/cheers/{uid}`) wired to FCM. `onCheersCreated` also increments `beers/{beerId}.cheersCount`.

- [x] **Step 1: Write failing tests**

`functions/test/emu/pushes.test.ts`:
```ts
import { describe, it, expect, beforeEach } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";
import { fanoutBeerCreated, notifyCheers, Pusher } from "../../src/pushes";

const db = initTestDb();
type Sent = { tokens: string[]; title: string; body: string };
let sent: Sent[] = [];
const push: Pusher = async (tokens, title, body) => { sent.push({ tokens, title, body }); };

beforeEach(async () => {
  await clearDb(db);
  sent = [];
  await seedUser(db, "owner", "tim", "tok-owner");
  await seedUser(db, "friend", "joost", "tok-friend");
  await seedUser(db, "blocker", "hans", "tok-blocker");
  await seedFriends(db, "owner", "friend");
  await seedFriends(db, "owner", "blocker");
  await db.doc("blocks/blocker/blocked/owner").set({ at: Timestamp.now() });
});

const beer = { ownerUid: "owner", ownerName: "Tim", hasPhoto: true };

describe("fanoutBeerCreated", () => {
  it("pushes to friends with photo copy, skips blockers", async () => {
    await fanoutBeerCreated(db, push, "b1", beer);
    expect(sent).toHaveLength(1);
    expect(sent[0].tokens).toEqual(["tok-friend"]);
    expect(sent[0].title).toContain("Tim is drinking a beer");
    expect(sent[0].body).toContain("📸");
  });
  it("no photo → plain copy", async () => {
    await fanoutBeerCreated(db, push, "b1", { ...beer, hasPhoto: false });
    expect(sent[0].body).not.toContain("📸");
  });
});

describe("notifyCheers", () => {
  it("pushes cheerser name to owner", async () => {
    await notifyCheers(db, push, "owner", "friend");
    expect(sent[0].tokens).toEqual(["tok-owner"]);
    expect(sent[0].title).toContain("joost");
  });
});
```

- [x] **Step 2: Run emulator gate** — Expected: FAIL.

- [x] **Step 3: Implement**

`functions/src/pushes.ts`:
```ts
import { Firestore } from "firebase-admin/firestore";

export type Pusher = (tokens: string[], title: string, body: string, data: Record<string, string>) => Promise<void>;

type BeerDoc = { ownerUid: string; ownerName: string; hasPhoto: boolean };

export async function fanoutBeerCreated(db: Firestore, push: Pusher, beerId: string, beer: BeerDoc) {
  const friends = await db.collection(`friendships/${beer.ownerUid}/friends`).get();
  const tokens: string[] = [];
  for (const f of friends.docs) {
    const blocked = await db.doc(`blocks/${f.id}/blocked/${beer.ownerUid}`).get();
    if (blocked.exists) continue;
    const token = (await db.doc(`users/${f.id}`).get()).get("fcmToken");
    if (token) tokens.push(token);
  }
  if (tokens.length === 0) return;
  const body = beer.hasPhoto ? "They added a photo 📸 — you get one look!" : "Cheers back? 🍻";
  await push(tokens, `${beer.ownerName} is drinking a beer 🍺`, body, { beerId });
}

export async function notifyCheers(db: Firestore, push: Pusher, beerOwnerUid: string, cheererUid: string) {
  const [owner, cheerser] = await Promise.all([
    db.doc(`users/${beerOwnerUid}`).get(), db.doc(`users/${cheererUid}`).get(),
  ]);
  const token = owner.get("fcmToken");
  if (!token) return;
  await push([token], `${cheerser.get("usernameLower")} cheersed you 🍻`, "Proost!", {});
}
```

Add to `functions/src/index.ts`:
```ts
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { FieldValue } from "firebase-admin/firestore";
import { fanoutBeerCreated, notifyCheers, Pusher } from "./pushes";

const fcmPush: Pusher = async (tokens, title, body, data) => {
  await getMessaging().sendEachForMulticast({ tokens, notification: { title, body }, data });
};

export const onBeerCreated = onDocumentCreated("beers/{beerId}", async (event) => {
  const beer = event.data?.data();
  if (!beer) return;
  await fanoutBeerCreated(getFirestore(), fcmPush, event.params.beerId,
    beer as { ownerUid: string; ownerName: string; hasPhoto: boolean });
});

export const onCheersCreated = onDocumentCreated("beers/{beerId}/cheers/{uid}", async (event) => {
  const db = getFirestore();
  const beerRef = db.doc(`beers/${event.params.beerId}`);
  await beerRef.update({ cheersCount: FieldValue.increment(1) });
  const beer = await beerRef.get();
  if (beer.exists) await notifyCheers(db, fcmPush, beer.get("ownerUid"), event.params.uid);
});
```

- [x] **Step 4: Run emulator gate + build** — Expected: PASS.

**Review outcome (applied):** block filtering in `fanoutBeerCreated` is bidirectional (owner-blocked-friend AND friend-blocked-owner), matching `getPhotoOnce`; extra emulator test covers it. `vitest.config.ts` gained `fileParallelism: false` (all emu test files share one Firestore emulator + `clearDb`). **Task 8 must extend the rules the same way: `beers` read and `cheers` create must be denied when a block exists in either direction** (add block-negative rules tests).

- [x] **Step 5: Commit** — `git commit -am "feat(functions): push fanout for beers and cheers"`

### Task 7: Friendship mirror, expiry cleanup, account deletion

**Files:**
- Create: `functions/src/lifecycle.ts`
- Modify: `functions/src/index.ts`
- Test: `functions/test/emu/lifecycle.test.ts`

**Interfaces:**
- Consumes: harness (Task 4).
- Produces: `mirrorFriendship(db, uid, friendUid)`; `cleanupExpiredCore(db, deletePhoto, now) => Promise<number>` (returns count deleted; `deletePhoto: (path: string) => Promise<void>`); `deleteAccountCore(db, deletePhoto, uid)`. Exports: trigger `onFriendAccepted` (`friendships/{uid}/friends/{friendUid}` created → mirror + delete the incoming request), scheduled `cleanupExpired` (hourly), callable `deleteAccount`.

- [x] **Step 1: Write failing tests**

`functions/test/emu/lifecycle.test.ts`:
```ts
import { describe, it, expect, beforeEach } from "vitest";
import { Timestamp } from "firebase-admin/firestore";
import { initTestDb, seedUser, seedFriends, clearDb } from "./helpers";
import { mirrorFriendship, cleanupExpiredCore, deleteAccountCore } from "../../src/lifecycle";

const db = initTestDb();
let deletedPhotos: string[] = [];
const deletePhoto = async (p: string) => { deletedPhotos.push(p); };
const NOW = new Date("2026-07-11T12:00:00Z");

beforeEach(async () => { await clearDb(db); deletedPhotos = []; });

async function seedBeer(id: string, owner: string, hoursOld: number, hasPhoto = true) {
  const created = new Date(NOW.getTime() - hoursOld * 3600_000);
  await db.doc(`beers/${id}`).set({
    ownerUid: owner, ownerName: owner, hasPhoto, photoPath: `photos/${id}.jpg`,
    cheersCount: 0, createdAt: Timestamp.fromDate(created),
    expiresAt: Timestamp.fromDate(new Date(created.getTime() + 24 * 3600_000)),
  });
  await db.doc(`beers/${id}/views/somebody`).set({ viewedAt: Timestamp.fromDate(NOW) });
}

describe("mirrorFriendship", () => {
  it("writes reverse edge and clears request", async () => {
    await db.doc("friendRequests/u1/incoming/u2").set({ sentAt: Timestamp.now() });
    await db.doc("friendships/u1/friends/u2").set({ since: Timestamp.now() });
    await mirrorFriendship(db, "u1", "u2");
    expect((await db.doc("friendships/u2/friends/u1").get()).exists).toBe(true);
    expect((await db.doc("friendRequests/u1/incoming/u2").get()).exists).toBe(false);
  });
});

describe("cleanupExpiredCore", () => {
  it("deletes only expired beers, their photos and subcollections", async () => {
    await seedBeer("old", "u1", 25);
    await seedBeer("fresh", "u1", 1);
    const n = await cleanupExpiredCore(db, deletePhoto, NOW);
    expect(n).toBe(1);
    expect((await db.doc("beers/old").get()).exists).toBe(false);
    expect((await db.doc("beers/old/views/somebody").get()).exists).toBe(false);
    expect((await db.doc("beers/fresh").get()).exists).toBe(true);
    expect(deletedPhotos).toEqual(["photos/old.jpg"]);
  });
});

describe("deleteAccountCore", () => {
  it("erases user, username, friendships both sides, beers+photos", async () => {
    await seedUser(db, "u1", "tim");
    await seedUser(db, "u2", "joost");
    await seedFriends(db, "u1", "u2");
    await seedBeer("b1", "u1", 1);
    await deleteAccountCore(db, deletePhoto, "u1");
    expect((await db.doc("users/u1").get()).exists).toBe(false);
    expect((await db.doc("usernames/tim").get()).exists).toBe(false);
    expect((await db.doc("friendships/u2/friends/u1").get()).exists).toBe(false);
    expect((await db.doc("beers/b1").get()).exists).toBe(false);
    expect(deletedPhotos).toEqual(["photos/b1.jpg"]);
  });
});
```

- [x] **Step 2: Run emulator gate** — Expected: FAIL.

- [x] **Step 3: Implement**

`functions/src/lifecycle.ts`:
```ts
import { Firestore, Timestamp } from "firebase-admin/firestore";

export type PhotoDeleter = (path: string) => Promise<void>;

export async function mirrorFriendship(db: Firestore, uid: string, friendUid: string) {
  await db.doc(`friendships/${friendUid}/friends/${uid}`).set({ since: Timestamp.now() });
  await db.doc(`friendRequests/${uid}/incoming/${friendUid}`).delete();
}

async function deleteBeer(db: Firestore, deletePhoto: PhotoDeleter, beerId: string, photoPath?: string, hasPhoto?: boolean) {
  if (hasPhoto && photoPath) await deletePhoto(photoPath).catch(() => {});
  await db.recursiveDelete(db.doc(`beers/${beerId}`));
}

export async function cleanupExpiredCore(db: Firestore, deletePhoto: PhotoDeleter, now: Date = new Date()): Promise<number> {
  const expired = await db.collection("beers").where("expiresAt", "<=", Timestamp.fromDate(now)).get();
  for (const doc of expired.docs) {
    await deleteBeer(db, deletePhoto, doc.id, doc.get("photoPath"), doc.get("hasPhoto"));
  }
  return expired.size;
}

export async function deleteAccountCore(db: Firestore, deletePhoto: PhotoDeleter, uid: string) {
  const user = await db.doc(`users/${uid}`).get();
  const username = user.get("usernameLower");
  const beers = await db.collection("beers").where("ownerUid", "==", uid).get();
  for (const b of beers.docs) await deleteBeer(db, deletePhoto, b.id, b.get("photoPath"), b.get("hasPhoto"));
  const myFriends = await db.collection(`friendships/${uid}/friends`).listDocuments();
  for (const f of myFriends) await db.doc(`friendships/${f.id}/friends/${uid}`).delete();
  await db.recursiveDelete(db.doc(`friendships/${uid}`));
  await db.recursiveDelete(db.doc(`friendRequests/${uid}`));
  await db.recursiveDelete(db.doc(`blocks/${uid}`));
  if (username) await db.doc(`usernames/${username}`).delete();
  await db.doc(`users/${uid}`).delete();
}
```

Add to `functions/src/index.ts`:
```ts
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getAuth } from "firebase-admin/auth";
import { mirrorFriendship, cleanupExpiredCore, deleteAccountCore, PhotoDeleter } from "./lifecycle";

const storagePhotoDeleter: PhotoDeleter = async (path) => {
  await getStorage().bucket().file(path).delete({ ignoreNotFound: true });
};

export const onFriendAccepted = onDocumentCreated("friendships/{uid}/friends/{friendUid}", async (event) => {
  await mirrorFriendship(getFirestore(), event.params.uid, event.params.friendUid);
});

export const cleanupExpired = onSchedule("every 60 minutes", async () => {
  await cleanupExpiredCore(getFirestore(), storagePhotoDeleter);
});

export const deleteAccount = onCall(async (req) => {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in required");
  await deleteAccountCore(getFirestore(), storagePhotoDeleter, req.auth.uid);
  await getAuth().deleteUser(req.auth.uid);
  return { ok: true };
});
```
Note: `mirrorFriendship` sets the reverse edge, which re-fires `onFriendAccepted` once for the mirror; the second invocation's `set` is idempotent and its request-delete is a no-op, so it terminates.

- [x] **Step 4: Run emulator gate + build** — Expected: PASS.

**Review outcome (applied):** `deleteAccountCore` also purges traces of the user under OTHER users' docs via collection-group queries: friend requests they SENT (`incoming` where `fromUid == uid`) and `cheers`/`views` they left on friends' beers (`uid` field). **Contract for Tasks 8/9:** cheers docs are `{uid, at}` and incoming-request docs are `{fromUid, fromUsername, fromDisplayName, sentAt}` — Task 8 rules MUST require `request.resource.data.uid == me()` on cheers create and `request.resource.data.fromUid == me()` on request create; Task 9 clients MUST write these fields. `getPhotoOnce` view records now include `uid`. New `firestore.indexes.json` (composite beers hasPhoto+allViewedAt; collection-group fieldOverrides for incoming.fromUid, cheers.uid, views.uid) wired into firebase.json — deploy includes it. `cleanupExpiredCore` bounds each run to 500 docs per query and isolates per-doc failures; returns count of deleted expired docs only. `deleteAccount` callable: Firestore-first ordering, idempotent retry (throws RETRY_DELETE if auth deletion fails after data erasure). 8 lifecycle tests.

- [x] **Step 5: Commit** — `git commit -am "feat(functions): friendship mirror, cleanup, account deletion"`

---

## Milestone 3 — Security rules

### Task 8: Firestore + Storage rules with rules-unit-testing

**Files:**
- Modify: `firestore.rules`, `storage.rules` (replace Task 1 permissive placeholders)
- Create: `functions/test/emu/rules.test.ts`
- Modify: `functions/package.json` (add `@firebase/rules-unit-testing` + `firebase` to devDependencies)

**Interfaces:**
- Consumes: schema from spec §2.
- Produces: locked rules relied on by Tasks 9–10 (clients write only what rules allow; photo reads impossible client-side).

- [x] **Step 1: Write failing rules tests**

`functions/test/emu/rules.test.ts`:
```ts
import { describe, it, beforeAll, afterAll, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import {
  initializeTestEnvironment, assertSucceeds, assertFails, RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc } from "firebase/firestore";
import { ref, getBytes } from "firebase/storage";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-beerwithme",
    firestore: { rules: readFileSync("../firestore.rules", "utf8") },
    storage: { rules: readFileSync("../storage.rules", "utf8") },
  });
});
afterAll(() => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "friendships/owner/friends/friend"), { since: 1 });
    await setDoc(doc(db, "beers/b1"), { ownerUid: "owner", ownerName: "Tim", hasPhoto: true, photoPath: "photos/b1.jpg", cheersCount: 0, createdAt: 1, expiresAt: 9999999999999 });
  });
});

describe("firestore rules", () => {
  it("friend reads beer; stranger cannot", async () => {
    await assertSucceeds(getDoc(doc(env.authenticatedContext("friend").firestore(), "beers/b1")));
    await assertFails(getDoc(doc(env.authenticatedContext("stranger").firestore(), "beers/b1")));
    await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(), "beers/b1")));
  });
  it("only owner creates own beer with matching ownerUid", async () => {
    const me = env.authenticatedContext("owner").firestore();
    await assertSucceeds(setDoc(doc(me, "beers/b2"), { ownerUid: "owner", ownerName: "Tim", hasPhoto: false, photoPath: "", cheersCount: 0, createdAt: 1, expiresAt: 2 }));
    await assertFails(setDoc(doc(me, "beers/b3"), { ownerUid: "someone-else", ownerName: "X", hasPhoto: false, photoPath: "", cheersCount: 0, createdAt: 1, expiresAt: 2 }));
  });
  it("views are function-only (no client writes)", async () => {
    await assertFails(setDoc(doc(env.authenticatedContext("friend").firestore(), "beers/b1/views/friend"), { viewedAt: 1 }));
  });
  it("username reservation is create-once with own uid", async () => {
    const me = env.authenticatedContext("u9").firestore();
    await assertSucceeds(setDoc(doc(me, "usernames/newname"), { uid: "u9" }));
    await assertFails(setDoc(doc(me, "usernames/othername"), { uid: "someone-else" }));
  });
  it("friend request: sender creates, recipient reads", async () => {
    await assertSucceeds(setDoc(doc(env.authenticatedContext("friend").firestore(), "friendRequests/owner/incoming/friend"), { sentAt: 1 }));
    await assertSucceeds(getDoc(doc(env.authenticatedContext("owner").firestore(), "friendRequests/owner/incoming/friend")));
    await assertFails(setDoc(doc(env.authenticatedContext("imposter").firestore(), "friendRequests/owner/incoming/friend"), { sentAt: 1 }));
  });
});

describe("storage rules", () => {
  it("nobody reads photos directly — not even the owner", async () => {
    await assertFails(getBytes(ref(env.authenticatedContext("owner").storage(), "photos/b1.jpg")));
    await assertFails(getBytes(ref(env.authenticatedContext("friend").storage(), "photos/b1.jpg")));
  });
});
```

- [x] **Step 2: `npm --prefix functions install -D @firebase/rules-unit-testing firebase` then run emulator gate** — Expected: rules tests FAIL against the permissive placeholder (the "stranger cannot" / "views" assertions fail).

- [x] **Step 3: Write real rules**

`firestore.rules`:
```
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function me() { return request.auth.uid; }
    function isFriendOf(ownerUid) {
      return exists(/databases/$(db)/documents/friendships/$(ownerUid)/friends/$(me()));
    }

    match /users/{uid} {
      allow read: if signedIn();
      allow create, update: if signedIn() && me() == uid;
      allow delete: if false;
    }

    match /usernames/{name} {
      allow read: if signedIn();
      allow create: if signedIn() && request.resource.data.uid == me();
      allow update, delete: if false;
    }

    match /friendRequests/{uid}/incoming/{fromUid} {
      allow read: if signedIn() && me() == uid;
      allow create: if signedIn() && me() == fromUid && uid != fromUid;
      allow delete: if signedIn() && (me() == uid || me() == fromUid);
    }

    match /friendships/{uid}/friends/{friendUid} {
      allow read: if signedIn() && (me() == uid || me() == friendUid);
      // accept = recipient materializes the edge; function mirrors the reverse
      allow create: if signedIn() && me() == uid
        && exists(/databases/$(db)/documents/friendRequests/$(uid)/incoming/$(friendUid));
      allow delete: if signedIn() && (me() == uid || me() == friendUid);
    }

    match /beers/{beerId} {
      allow read: if signedIn() && (resource.data.ownerUid == me() || isFriendOf(resource.data.ownerUid));
      allow create: if signedIn() && request.resource.data.ownerUid == me()
        && request.resource.data.keys().hasAll(['ownerUid','ownerName','createdAt','expiresAt','hasPhoto','photoPath','cheersCount'])
        && request.resource.data.cheersCount == 0;
      allow update: if false;
      allow delete: if signedIn() && resource.data.ownerUid == me();

      match /views/{viewerUid} {
        allow read: if signedIn() && (viewerUid == me()
          || get(/databases/$(db)/documents/beers/$(beerId)).data.ownerUid == me());
        allow write: if false;  // getPhotoOnce (admin SDK) only
      }

      match /cheers/{uid} {
        allow read: if signedIn();
        allow create: if signedIn() && me() == uid
          && isFriendOf(get(/databases/$(db)/documents/beers/$(beerId)).data.ownerUid);
        allow update, delete: if false;
      }
    }

    match /blocks/{uid}/blocked/{other} {
      allow read, create, delete: if signedIn() && me() == uid;
      allow update: if false;
    }

    match /reports/{reportId} {
      allow create: if signedIn() && request.resource.data.reporterUid == me();
      allow read, update, delete: if false;
    }
  }
}
```

`storage.rules`:
```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /photos/{photo} {
      allow read: if false;  // signed URLs from getPhotoOnce only
      allow create: if request.auth != null
        && request.resource.size < 5 * 1024 * 1024
        && request.resource.contentType == 'image/jpeg';
      allow update, delete: if false;
    }
    match /{everythingElse=**} { allow read, write: if false; }
  }
}
```

- [x] **Step 4: Run emulator gate** — Expected: ALL tests pass (Tasks 4–8 suites).

**Review outcome (applied, adversarial security review — 5 MUST-FIX):** (1) beer create now schema-validated: `hasOnly` seven keys, `createdAt == request.time` (**Task 9: createdAt MUST be `FieldValue.serverTimestamp()`**), `expiresAt is timestamp`, `> request.time`, `<= request.time + 25h` (**Task 9: compute expiresAt client-side as now+24h Timestamp**) — kills immortal beers that cleanup could never match; (2) **design change: blocking severs friendship** — new `severOnBlock` + `onBlockCreated` trigger delete both friendship edges and pending requests both directions; beers/cheers/screenshots rules gate on friendship only (keeps the feed `in`-query inside the rules get() budget; photo.ts/pushes.ts block checks remain as defense in depth). **Task 9 `FriendServicing.block` just writes the block doc — the server does the unfriending**; (3) cheers/screenshots reads gated by owner-or-friend (were world-readable — leaked social graph); (4) **fcmToken moved to `users/{uid}/private/push` field `token`** (was scrapeable by any signed-in user); `users`/`usernames` are get-only (`list: false` — no directory dumping); **Task 9 PushRegistrar writes users/{uid}/private/push {token}`**; (5) friend-request create checks blocks + full schema; usernames create is anti-squat (one reservation per account). 41 rules tests incl. multi-owner feed `in` query. Emulator suite: 68/68.

- [x] **Step 5: Commit** — `git commit -am "feat(rules): lock down Firestore and Storage"`

---

## Milestone 4 — SwiftUI app shell (compile-parked: review + BeerKit-green gates only)

### Task 9: App entry, routing, Firebase service implementations

**Files:**
- Create: `App/Sources/BeerWithMeApp.swift`, `App/Sources/AppState.swift`, `App/Sources/Services/FirebaseAuthService.swift`, `App/Sources/Services/FirebaseBeerService.swift`, `App/Sources/Services/FirebaseFriendService.swift`, `App/Sources/Services/PushRegistrar.swift`

**Interfaces:**
- Consumes: `AuthServicing`, `BeerServicing`, `FriendServicing`, `PhotoFetchError`, models — exactly as defined in Tasks 2–3.
- Produces: concrete `FirebaseAuthService: AuthServicing`, `FirebaseBeerService: BeerServicing`, `FirebaseFriendService: FriendServicing`; `AppState` published enum `phase: .loading/.signedOut/.needsUsername/.ready(UserProfile)`. Task 10 views consume `AppState` + the protocols only (never Firebase types directly).

Key requirements the implementer must honor (full Firebase SDK code, ~350 lines total):
- `FirebaseBeerService.logBeer(photoJPEG:)`: generate `beerId = UUID().uuidString.lowercased()`; if photo present, upload to `photos/{beerId}.jpg` (metadata contentType `image/jpeg`) BEFORE creating the Firestore doc; doc fields exactly: `ownerUid, ownerName, createdAt (server timestamp), expiresAt (createdAt+24h computed client-side as Timestamp), hasPhoto, photoPath, cheersCount: 0`. Increment `users/{uid}.beerCount` after.
- `observeFeed()`: snapshot listener on `beers` where `ownerUid in` (my uid + friend uids, chunked by 30 for the `in` limit) and `expiresAt > now`, wrapped in `AsyncStream`.
- `fetchPhotoOnce(beerId:)`: call callable `getPhotoOnce`; map `HttpsError` message codes `ALREADY_VIEWED→.alreadyViewed`, `EXPIRED→.expired`, `NOT_FRIENDS→.notFriends`, else `.notFound`.
- `FirebaseAuthService.claimUsername`: batched write — create `usernames/{name}` + `users/{uid}` together so the rules' create-once makes the pair atomic; surface a `UsernameTakenError` on permission-denied.
- `PushRegistrar`: request notification permission, register FCM token into `users/{uid}.fcmToken` on launch and on token refresh.
- `AppState`: listens to Auth state; loads `users/{uid}` to decide `.needsUsername` vs `.ready`.

- [ ] **Step 1: Implement all files per requirements above** (no compile gate available — write carefully against the protocol signatures).
- [ ] **Step 2: Run `cd BeerKit && swift test`** — Expected: still PASS (App/ is outside the package; this guards accidental BeerKit edits).
- [ ] **Step 3: Reviewer pass** (code-reviewer subagent on the diff; fix must-fix findings).
- [ ] **Step 4: Commit** — `git commit -am "feat(app): entry, app state, Firebase services (compile-parked)"`

### Task 10: Screens — Onboarding, Home/Feed, Camera, PhotoViewer, Friends, Settings

**Files:**
- Create: `App/Sources/Views/OnboardingView.swift` (Sign in with Apple button + username picker with live availability), `App/Sources/Views/HomeView.swift` (big log button, camera shortcut, feed rows with chip states + cheers), `App/Sources/Views/CameraView.swift` (AVFoundation `UIViewControllerRepresentable`, front/back flip, retake/send, JPEG ≤1080p @ 0.8), `App/Sources/Views/PhotoViewerView.swift` (full-screen once-only display; on screenshot — `UIApplication.userDidTakeScreenshotNotification` — fire-and-forget write to `beers/{beerId}/screenshots/{myUid}` which the owner's feed row surfaces as "«name» took a screenshot 👀"; add a matching create-only rule for `screenshots/{uid}` mirroring the `cheers` rule in Task 8's `firestore.rules`), `App/Sources/Views/FriendsView.swift` (list, requests, search, invite ShareLink), `App/Sources/Views/SettingsView.swift` (profile, blocked list, delete account with confirmation, privacy policy link)

**Interfaces:**
- Consumes: `HomeViewModel`, `AppState`, `FriendServicing`, `PhotoChipState` from Tasks 3 & 9 — views never import Firebase.
- Produces: complete UI; `PhotoViewerView(url:ownerName:onDismiss:)`; `CameraView(onCapture: (Data) -> Void)`.

- [ ] **Step 1: Implement all views.** Chip UI mapping: `.sealed` → filled "📸 view once" button; `.seen` → greyed "seen"; `.expired`/`.none` → nothing. `openPhoto` nil result → show `errorMessage` alert.
- [ ] **Step 2: Run `cd BeerKit && swift test`** — Expected: PASS.
- [ ] **Step 3: Reviewer pass; fix findings.**
- [ ] **Step 4: Commit** — `git commit -am "feat(app): all screens (compile-parked)"`

---

## Milestone 5 — Compliance + handover

### Task 11: UGC compliance + privacy artifacts

**Files:**
- Modify: `App/Sources/Views/HomeView.swift` (report/block context menu on every feed row), `App/Sources/Views/FriendsView.swift` (block from friend row)
- Create: `docs/privacy-policy.md` (ephemeral photos, data collected, deletion), `docs/app-store-checklist.md` (17+ rating, UGC boxes, App Privacy labels, screenshots list)

**Interfaces:**
- Consumes: `FriendServicing.block/report` (Task 3 protocol, Task 9 impl).

- [ ] **Step 1: Wire report + block context menus** (report reasons: "Not a beer 🚨", "Inappropriate photo", "Harassment", "Other").
- [ ] **Step 2: Write privacy policy + App Store checklist docs.**
- [ ] **Step 3: `cd BeerKit && swift test`** — PASS; reviewer pass.
- [ ] **Step 4: Commit** — `git commit -am "feat: UGC compliance + privacy artifacts"`

### Task 12: Runbook for Tim + final review + handover

**Files:**
- Create: `docs/RUNBOOK.md` — exact steps for Tim: install Xcode; `brew install xcodegen && xcodegen`; create Firebase project (Blaze), add iOS app, download `GoogleService-Info.plist` into `App/`; enable Sign in with Apple capability + APNs key upload to FCM; `firebase deploy --only functions,firestore:rules,storage`; TestFlight → App Store submission checklist.
- Modify: `STATE.md`, `README.md`

- [ ] **Step 1: Write RUNBOOK.md** (every command exact; nothing assumed).
- [ ] **Step 2: Full gate run** — `cd BeerKit && swift test` AND emulator gate AND `npm --prefix functions run build`. Expected: all PASS.
- [ ] **Step 3: Final reviewer pass over the whole repo** (code-review skill, high effort).
- [ ] **Step 4: Update STATE.md → all done except compile-parked items; list "Needs Tim" actions. Commit.**
