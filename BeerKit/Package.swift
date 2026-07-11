// swift-tools-version:5.9
import PackageDescription

// Broken-CLT workaround (this Mac only; see README "Note (this Mac)"): the CLT's
// usr/include/swift ships two modulemaps that both define SwiftBridging, which
// breaks every swiftinterface build (e.g. `import Foundation`). When the gate is
// run with SWIFTPM_CUSTOM_LIBS_DIR (the broken-CLT signal), shadow the stale
// modulemap via a VFS overlay in tools/. Unset (e.g. once Xcode is installed),
// no unsafe flags are added and the package is usable as a normal dependency.
let cltFixSettings: [SwiftSetting]
if let libsDir = Context.environment["SWIFTPM_CUSTOM_LIBS_DIR"] {
    let overlay = libsDir + "/../clt-fix-overlay.yaml"
    cltFixSettings = [.unsafeFlags(["-vfsoverlay", overlay])]
} else {
    cltFixSettings = []
}

let package = Package(
    name: "BeerKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "BeerKit", targets: ["BeerKit"])],
    targets: [
        .target(name: "BeerKit", swiftSettings: cltFixSettings),
        .testTarget(name: "BeerKitTests", dependencies: ["BeerKit"], swiftSettings: cltFixSettings),
    ]
)
