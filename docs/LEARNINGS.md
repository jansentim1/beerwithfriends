# Learnings

Hard-won, project-specific. Newest first.

## 2026-09-07: push notifications took five TestFlight rounds

What happened: builds 6 to 11 each carried one guess about why the Apple device token
never reached the server, and Tim had to install, relaunch and report every time. The
real causes only became visible once the app wrote its status and errors to the server.

Rules from now on:

1. **Diagnostics before the first device build.** Any feature only a real iPhone can
   exercise (push, camera, Sign in with Apple, deep links) ships with status + last
   error written to `users/{uid}/private/...`, readable from tim-server. One build to
   learn, not five.
2. **Say what is verified.** Unit tests, emulator tests and CI screenshots are verified.
   Device behaviour is assumed until Tim confirms. Never announce a device-only fix as
   working.
3. **Batch.** One build carries every plausible fix plus diagnostics, with a single
   three-step checklist for Tim.
4. **Stack pitfalls (this project):**
   - SwiftUI + Firebase: set `FirebaseAppDelegateProxyEnabled` to false and hand
     `Messaging.messaging().apnsToken` over yourself; register with APNs regardless
     of the alert permission.
   - Signed Storage URLs from Cloud Functions need `iam.serviceAccounts.signBlob`,
     which tim-server cannot grant; the function returns the photo bytes instead.
   - FCM's APNs key upload has no API; delivery goes straight to APNs (`functions/src/apns.ts`).
   - `firebase functions:secrets:set` works, but the deploy-time access grant needs
     project IAM; the function reads Secret Manager at runtime instead.
   - Claude's auto mode refuses production wipes and interactive logins; anything only
     Tim may do gets a script with a `--yes` flag, run via `! ...` (no stdin there).
5. **Photos:** the function must obtain the photo before recording the one view, or a
   delivery failure burns the view.

## 2026-09-07: no Mac needed

GitHub-hosted macOS runners compile, test (simulator + Firebase emulators, screenshot
artifacts) and ship to TestFlight. Automatic signing fails without a registered device;
a distribution certificate and App Store profile created through the App Store Connect
API, stored as secrets, and applied only to the app target (not SwiftPM targets) work.

## 2026-09-04: blind-written SwiftUI compiled first time

2,400 lines written without a compiler compiled clean on the first cloud build. Cheap
compile checks (5 min, free on a public repo) beat careful reasoning about SDK signatures.

## Auth emulator: accounts live in the `--project` namespace (2026-09-10)
The Firestore and Storage emulators namespace by whatever project id the client names (the iOS app uses the plist's beerwithme-prod, and admin-SDK seeds must match). The Auth emulator does not: `getProjectIdByApiKey` returns the emulator's default project for every API-key request, so app sign-ins always land in demo-pubdates. A seed that creates users under beerwithme-prod produces EMAIL_NOT_FOUND in the app. `tools/rig/seed.mjs` uses a second admin app (projectId demo-pubdates) for Auth only. Verify sign-in with a plain curl to `accounts:signInWithPassword?key=anything` before blaming the app.

## Rig: one project id for app, seed and emulators (2026-09-15)
The functions emulator serves callables only under `/<its --project>/<region>/<name>`, and the Firestore triggers it registers are for that project too. The iOS SDK builds callable URLs from the plist's project id. So in emulator mode the app now configures Firebase with `demo-pubdates` (EmulatorConfig.configureFirebase), the seed writes to `demo-pubdates`, and the emulators start with `--project demo-pubdates`. That supersedes the 2026-09-10 auth-namespace workaround: no more split admin apps.

## Draw glass silhouettes locally, not on the rig (2026-09-17)
Tuning a bezier through the screenshot rig costs ~6 minutes a round and the crop is small. `tools/glassdraw.py` mirrors `DrinkGlassGeometry.bowlPath`'s unit box (0…1, y down) and its move/line/quad/curve commands in Pillow, so a shape can be judged in a second and only the settled numbers go to Swift. Two shapes that looked fine in code (a nonic "bulge" and a tulip "waist") rendered as a bolt and an hourglass; both were obvious at the first local render.

Also: a Python edit that replaces `s[s.index(a):s.index(b)]` silently truncates the file when the slice is assigned back wrong. It shipped a DrinkGlass.swift of 726 lines that began mid-`switch`. Prefer exact `str.replace(old, new, 1)` with an `assert old in s`, and check `head -2` of the file after any structural edit.

