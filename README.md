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

A second CLT defect: `usr/include/swift/module.modulemap` (stale) and `bridging.modulemap` both define module `SwiftBridging`, which breaks every swiftinterface build (the first `import Foundation` dies with a misleading "SDK not supported by the compiler" error). `BeerKit/Package.swift` shadows the stale modulemap via the VFS overlay `tools/clt-fix-overlay.yaml` — but only when `SWIFTPM_CUSTOM_LIBS_DIR` is set, so the package stays a normal dependency once Xcode is installed. The real fix for both defects: reinstall CLT, or install Xcode.

## Developing on tim-server (Linux)

`ssh tim-server`, repo at `~/beerwithme` (origin uses the `github-beerwithme` SSH alias, a
write deploy key). Toolchain lives in the home dir, on PATH via `~/.bashrc`: Swift via
swiftly (`~/.local/share/swiftly`), Temurin JDK 21 (`~/.local/jdk/current`, firebase-tools
refuses < 21; the apt JDK 17 is still installed but shadowed), `firebase` from
`npm -g --prefix ~/.local`, Node 20 from apt. All three gates run unchanged there; plain
`swift test` works (no CLT workaround needed). Only BeerKit and functions build on Linux;
the SwiftUI `App` target needs Xcode. The Firestore emulator is on port 8085 because the
WhatsApp bridge on the server owns 8080.

Emulator gate (from repo root):

```
npx firebase-tools emulators:exec --project demo-beerwithme --only firestore,auth,storage "npm --prefix functions run test:emu"
```
