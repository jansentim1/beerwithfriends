# BeerWithMe

iPhone app: tap to log a beer → friends get a push and can cheers back; optionally attach a live camera photo that each friend can view exactly once (server-enforced), expiring after 24 hours. The testable core lives in the local Swift package `BeerKit`; the backend is Firebase (Firestore, Storage, TypeScript Cloud Functions) locked down by security rules.

## Gates

```
cd BeerKit && swift test
cd functions && npm test
```

**Note (this Mac):** the installed Command Line Tools are a broken mixed install (Swift 5.10 private swiftinterfaces alongside 6.0.3 dylibs), so plain `swift test` fails to compile any Package.swift manifest. Until the CLT is reinstalled (or Xcode installed), run the Swift gate as:

```
cd BeerKit && SWIFTPM_CUSTOM_LIBS_DIR="$(git rev-parse --show-toplevel)/tools/swiftpm-libs" swift test
```

`tools/swiftpm-libs/` is a local (gitignored) copy of the CLT SwiftPM libs with the stale 5.10 private interfaces removed. Regenerate it with:

```
cp -R /Library/Developer/CommandLineTools/usr/lib/swift/pm/ tools/swiftpm-libs/
find tools/swiftpm-libs -name '*.private.swiftinterface' -delete
```

Tests use Swift Testing (`import Testing`) rather than XCTest, because the CLT does not ship XCTest (it never has — XCTest requires Xcode).

Emulator gate (from repo root):

```
npx firebase-tools emulators:exec --project demo-beerwithme --only firestore,auth,storage "npm --prefix functions run test:emu"
```
