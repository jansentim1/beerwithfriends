# BeerWithMe Clone + Disappearing Photos — Design Spec

Date: 2026-07-11
Status: Approved by Tim (approach A; sections 2–3 approved implicitly via "make a plan")

## 1. Product summary

A native iPhone app (App Store release) that copies the social core of
BeerWithMe and adds a Snapchat-style disappearing photo:

- Tap one button to log a beer. All friends get a push notification and can
  "cheers" (🍻) back, which pushes back to the drinker.
- Optionally attach a **live camera photo** to the log (camera only — no photo
  library, so photos are always in-the-moment).
- Each friend can view the photo **exactly once** (view-once), enforced
  server-side. Unviewed photos expire after 24 hours. Expired/viewed photos are
  actually deleted, not hidden.
- Sign in with Apple + unique username. Friends are added by username search
  or invite link — no contacts access.

Decisions locked with Tim:
- Core scope: social "cheers" loop (not a full stats/leaderboards clone).
- Photo rules: view-once per friend, 24h expiry for unviewed.
- Capture: photo optional, camera-only.
- Backend: Firebase (approach A — server-enforced disappearing, Blaze plan).
- Distribution: App Store.
- Auth: Sign in with Apple + username.

## 2. Architecture

**Client:** SwiftUI, iOS 17+, MVVM. Firebase iOS SDK (Auth, Firestore,
Storage, Messaging) via SPM. AVFoundation camera.

All business logic lives in a local Swift Package **`BeerKit`** (models,
validation, view models, protocol-based service interfaces) that builds and
tests on macOS with `swift test` — no Xcode or Firebase required. The app
target is a thin SwiftUI shell + Firebase-backed implementations of the
`BeerKit` service protocols.

**Backend (Firebase project, Blaze plan):**

Firestore:
- `users/{uid}` — usernameLower, displayName, fcmToken, beerCount, createdAt.
- `usernames/{usernameLower}` — reservation doc → uid (uniqueness).
- `friendships/{uid}/friends/{friendUid}` — accepted friendships (written
  symmetrically by a Cloud Function on accept).
- `friendRequests/{uid}/incoming/{fromUid}` — pending requests.
- `beers/{beerId}` — ownerUid, createdAt, expiresAt (=createdAt+24h),
  hasPhoto, photoPath, cheersCount.
- `beers/{beerId}/views/{viewerUid}` — one-view records (written only by the
  `getPhotoOnce` function).
- `beers/{beerId}/cheers/{uid}` — cheers reactions.
- `reports/{reportId}` — abuse reports (App Store UGC requirement).
- `blocks/{uid}/blocked/{blockedUid}` — user blocks.

Storage: `photos/{beerId}.jpg` (JPEG ≤1080p, ~80% quality). **No client read
access at all** — rules deny all reads; only `getPhotoOnce`'s signed URLs work.
Client write access only for the owner at beer-creation time, ≤5MB,
content-type image/jpeg.

Cloud Functions (TypeScript, Node 20):
1. `onBeerCreated` (Firestore trigger) — fan out push to friends (excluding
   blocks): "«name» is drinking a beer 🍺" (+ "with a photo 📸").
2. `onCheersCreated` (trigger) — push to beer owner: "«name» cheersed you 🍻".
3. `onFriendRequestAccepted` (trigger) — write both sides of the friendship.
4. `getPhotoOnce` (callable) — the ONLY photo read path. Verifies: caller is a
   friend of the owner, not blocked, beer not expired, no existing view record.
   Transactionally writes `views/{callerUid}`, returns a ~60s signed URL.
   Second call → error PHOTO_ALREADY_VIEWED. When all friends have viewed,
   delete the photo object early.
5. `cleanupExpired` (scheduled, hourly) — delete photo objects + beer docs
   (and subcollections) past expiresAt.
6. `deleteAccount` (callable) — full account erasure: user doc, username
   reservation, friendships (both sides), beers + photos, tokens. (App Store
   5.1.1(v) requirement.)

Security rules enforce: users read/write self; usernames create-if-free;
beer docs readable only by owner's friends; views/cheers subcollections
writable only via function / owner-scoped; photos bucket: deny read, owner
create only.

## 3. Core flows

**Log a beer:** big button → optimistic local log → create `beers` doc
(+ upload photo first if taken, then doc with photoPath). Camera sheet is
one tap away from the button; skippable.

**Receive:** push arrives → app opens to feed. Feed = friends' non-expired
beers, newest first. Rows show name, time, 🍻 count, and a "photo" chip:
sealed (viewable), or "seen" (already used the one view). Tapping sealed chip
calls `getPhotoOnce`, shows the photo full-screen until dismissed (single
continuous viewing, no re-open), with `UIScreen.capturedDidChangeNotification`
+ screenshot detection best-effort notice to the owner ("«name» screenshotted
your photo"). Cheers button on each row.

**Friends:** search exact username → send request → accept/decline in a
requests tab. Block and report actions on every friend/beer row (UGC
compliance). Blocked users see nothing of yours and vice versa.

**Auth/onboarding:** Sign in with Apple → pick username (live availability
check) → notification permission primer → done. Account deletion button in
settings (calls `deleteAccount`).

**Failure handling:** no connectivity → beer logs queue locally (Firestore
offline persistence); `getPhotoOnce` failures map to friendly states
(expired / already viewed / not friends). Push token refresh handled on every
launch.

## 4. Screens

1. **Onboarding** — Sign in with Apple, username picker, notifications primer.
2. **Home/Feed** — big "🍺 I'm drinking a beer" button on top; friends' live
   beers below; camera shortcut on the button (long-press or adjacent icon).
3. **Camera** — full-screen AVFoundation capture, front/back flip, retake,
   send. No library picker.
4. **Photo viewer** — full-screen one-time view with owner name + timestamp.
5. **Friends** — list, requests, username search, invite share-link.
6. **Settings** — profile, notification prefs, blocked users, report history,
   delete account, privacy policy link.

## 5. App Store compliance checklist

- 17+ age rating (alcohol references); no purchase/ordering of alcohol.
- UGC (guideline 1.2): report content, block users, contact method — all in v1.
- Sign in with Apple (5.1.1) — it's the only login, compliant.
- Account deletion in-app (5.1.1(v)) — `deleteAccount` callable.
- Privacy: camera + notifications usage strings; privacy policy URL; App
  Privacy labels (identifiers, user content, usage data).
- Photos are ephemeral by design — stated in the privacy policy; deletion is
  real (verified by tests).

## 6. Testing strategy (the objective gates)

Borrowed from Project Dirk's scoreboard discipline: every milestone gate is a
**command with a numeric/boolean result**, not an LLM opinion.

1. `swift test` on `BeerKit` (macOS, no Xcode needed) — models, validation,
   view-model logic against protocol fakes.
2. `npm test` in `functions/` — unit + integration tests against the Firebase
   emulator suite (`firebase emulators:exec --project demo-beerwithme`), incl.
   the full view-once lifecycle: create → first view OK → second view rejected
   → expiry cleanup deletes.
3. Rules tests via `@firebase/rules-unit-testing` — friend can read beer doc,
   stranger cannot, nobody reads Storage photos directly, etc.
4. Xcode build + XCUITest smoke — **parked until Xcode is installed** (not on
   this Mac). Project generated with XcodeGen so it's `xcodegen && open` when
   available.

## 7. Out of scope (v1)

Stats/streaks/leaderboards, groups, Android, chat/replies beyond cheers,
video, filters/stickers, contact matching, multiple photos per beer.
