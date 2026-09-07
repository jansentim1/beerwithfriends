import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

/// Debug-only: `-UseEmulators` launch argument points every Firebase service at
/// the local emulator suite (UI tests on the CI simulator). Never compiled into
/// Release, so a TestFlight build cannot be redirected.
enum EmulatorConfig {
    static var isEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-UseEmulators")
        #else
        return false
        #endif
    }

    static let host = "127.0.0.1"

    /// Call right after `FirebaseApp.configure()`, before any service is touched.
    static func applyIfRequested() {
        #if DEBUG
        guard isEnabled else { return }
        Auth.auth().useEmulator(withHost: host, port: 9099)
        // Each UI test run starts signed out (the keychain survives reinstalls).
        try? Auth.auth().signOut()
        let settings = Firestore.firestore().settings
        settings.host = "\(host):8085"
        settings.isSSLEnabled = false
        settings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = settings
        Storage.storage().useEmulator(withHost: host, port: 9199)
        #endif
    }

    /// Functions instances are created per call site (region-pinned); route them too.
    static func functions(region: String) -> Functions {
        let functions = Functions.functions(region: region)
        #if DEBUG
        if isEnabled { functions.useEmulator(withHost: host, port: 5001) }
        #endif
        return functions
    }
}
