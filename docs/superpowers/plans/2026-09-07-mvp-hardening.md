# Pints With Mates: MVP hardening plan (speed, tests, design)

Date: 2026-09-07. Status: proposed, awaiting Tim's go.
Context: build 1 is on Tim's iPhone via TestFlight. Sign in works, logging a beer works but
feels laggy, the UI is the plain compile-first version. Everything runs from tim-server +
GitHub macOS runners + Tim's iPhone; no Mac (see docs/RUNBOOK.md).

Gates for every task: `cd BeerKit && swift test`, `npm --prefix functions test`, the emulator
gate, and a green `ios-build` run. Ship to TestFlight at the end of each milestone.

## Milestone A: make it fast (the lag)

### Task A1: Measure before guessing
- Add a Debug-only `Perf` signposter (os_signpost) around: auth state → profile loaded,
  `HomeViewModel.start()` → first feed render, `logBeer` tap → row visible, `logBeer` →
  server ack, `viewedBeerIds()` duration.
- Log the numbers with `print` in Debug so they show up in the on-device console via
  Settings → a hidden "diagnostics" row (copyable text). Tim pastes them back.

### Task A2: Optimistic logging (the main suspect)
`logBeer` today waits for two server round-trips (beer doc ack + beerCount increment)
before the row appears, and the feed listener needs its own round-trip on top.
- Insert the local `BeerLog` into `feed` immediately, id-deduped (review finding 1).
- Fire the Firestore write without awaiting the server ack (Firestore's latency
  compensation shows the pending doc to the listener instantly); surface failure via the
  existing error alert and roll the row back.
- Move the `beerCount` increment out of the tap path (best-effort background task).
- Photo path: upload runs in the background after the row is shown; hasPhoto flips on
  success (fixes the orphaned-photo ordering, review finding 9).

### Task A3: Feed startup in parallel
`start()` awaits `viewedBeerIds()` (friends read + N chunk queries + one get per photo
beer) before it subscribes to the feed. Subscribe first, resolve view state concurrently.
Replace the per-beer gets with one `views` collection-group read when rules allow, else
keep the gets but off the critical path.

### Task A4: Review findings 2 to 5 and the camera crash
- FCM token fetch on `setUser` (push works after first launch).
- Feed restarts owned by the view model (cancel + await), no 200 ms sleep; restart on
  listener error; `.active` scene check.
- Sign out / delete account never block on the push-token delete (2 s timeout).
- Guard `capturePhoto` on an active video connection.

### Task A5: Review findings 6 to 8 and 10
Profile-unavailable phase with retry; no request reload after accept; load existing
cheers; RETRY_DELETE handling with local sign-out.

## Milestone B: test everything

### Task B1: BeerKit unit tests for every A-task change
Dedupe, optimistic rollback, restart semantics, timeout on sign-out, cheers preload.

### Task B2: Functions
Emulator tests already cover rules and functions; add cases for anything A changes
(hasPhoto flip after upload if that moves server-side).

### Task B3: UI tests on the cloud Mac (`ios-test` workflow)
- XCUITest target `PintsUITests` driven by launch argument `-UseEmulators`: the app
  points Auth/Firestore/Storage/Functions at localhost and signs in with the Auth
  emulator's anonymous provider (Debug builds only, guarded by `#if DEBUG`).
- Workflow: boot iPhone simulator, start `firebase emulators` (Java is on the runner),
  seed two users + one friendship, run the suite, upload screenshots of every screen in
  light and dark mode as artifacts. I read the PNGs from tim-server.
- Flows covered: onboarding → username; log beer (no photo); feed shows friend's beer;
  cheers; view-once chip states; friends add/accept/decline; block/report; settings;
  delete account.
- Cost: ~12 macOS minutes per run. Manual trigger plus nightly.

### Task B4: On-device checklist (Tim + one friend)
A one-page checklist in docs/device-checklist.md: install, sign in, log, photo, cheers,
push both directions, view-once, expiry, block, delete. Two phones are needed for the
social loop; the friend joins through an external TestFlight group.

## Milestone C: design with impeccable (native iOS register)

### Task C1: Product context
`/impeccable init` → PRODUCT.md (register: product, platform: ios). Brand seed from the
icon's amber; one tint colour; SF type; semantic system colours; dark mode first-class.

### Task C2: Audit
`/impeccable audit` (native) over all six views using the B3 screenshots. Health score
and ranked findings committed to docs/design/audit-2026-09.md.

### Task C3: Polish per screen, in this order
1. Home: the log button is the product. Hero-sized, haptic on tap, a short "pouring"
   animation while pending, then the row slides in. Feed rows: name, relative time, chip
   states, cheers count as a proper pill; swipe actions for report/block; empty state
   that invites adding a friend.
2. Onboarding: two screens, large title, Sign in with Apple button at the natural
   thumb position, username field with live availability, notification explainer.
3. Camera: HIG-style shutter, flip, cancel; review step with retake/use.
4. Photo viewer: black, view-once badge, countdown-free (it's once, not timed).
5. Friends: inset grouped lists, request rows with accept/decline, search field,
   share link.
6. Settings: inset grouped, profile header, blocked users, sign out, delete (double
   confirm stays).
Cross-cutting: Dynamic Type, VoiceOver labels, reduced motion, dark mode, 44 pt targets.

### Task C4: Real app icon
Replace the generated placeholder with a designed one (impeccable asset producer agent,
1024 px, no alpha). Tim picks from three candidates sent via ntfy.

### Task C5: Verify
B3 screenshots before/after; TestFlight build; Tim's eyes.

## Milestone D: ship loop

- D1 Push: APNs key from Tim → uploaded to FCM from tim-server (API). Test both
  directions with the friend.
- D2 TestFlight build after A, after C. External group "Friends" for testers.
- D3 App Store: docs/app-store-checklist.md walk-through, screenshots from B3 or device.

## Budget and order

- Order: A2 → A4 → B1 → build 2 (Tim feels the difference) → A3, A5, B3 → C → build 3 → D.
- GitHub macOS minutes: A+B+C need roughly 25 runs this month, about 250 minutes,
  above the 200 free on a private repo. Options: make the repo public (unlimited free) or
  accept a few dollars. Tim decides.
- Needs Tim: APNs key; a second tester; icon choice; the public/private decision.
