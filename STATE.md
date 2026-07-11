# Loop state
- Current task: 1 (scaffold)
- Done: —
- Parked: —
- Needs Tim: install Xcode (App Store); later: real Firebase project (Blaze) + Apple Developer account.
- Needs Tim (env): Command Line Tools install is corrupted (Swift 5.10 private swiftinterfaces mixed with 6.0.3 dylibs, root-owned) — plain `swift test` cannot compile any Package.swift. Workaround in README (SWIFTPM_CUSTOM_LIBS_DIR + tools/swiftpm-libs). Fix permanently: reinstall CLT or install Xcode. Also: CLT has no XCTest, so BeerKit tests use Swift Testing (`import Testing`) instead of XCTest.
