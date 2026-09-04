# Loop state
- Current task: 10 (SwiftUI screens, compile-parked)
- Done: 1-8, 9 (app services; reviewed: Swift6 isolation fix, push-token clearing, contracts verified)
- Parked: —
- Needs Tim: install Xcode (App Store, Mac only); Apple Developer account (Sign in with Apple provider, APNs key for FCM); gh PAT on tim-server for PRs (see README).
- Done 2026-09-04: Firebase project beerwithme-prod (Blaze, europe-west4) created; rules + 7 functions deployed from tim-server via tools/deploy.sh; tim-server is the full-dev box (see README).
- Needs Tim (env): Command Line Tools install is corrupted (Swift 5.10 private swiftinterfaces mixed with 6.0.3 dylibs, root-owned) — plain `swift test` cannot compile any Package.swift. Workaround in README (SWIFTPM_CUSTOM_LIBS_DIR + tools/swiftpm-libs). Fix permanently: reinstall CLT or install Xcode. Also: CLT has no XCTest, so BeerKit tests use Swift Testing (`import Testing`) instead of XCTest.
