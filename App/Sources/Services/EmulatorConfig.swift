import FirebaseAuth
import FirebaseCore
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
    /// The one namespace the whole rig shares: the app (this), the seed
    /// (tools/rig/seed.mjs), and the emulators' `--project`. The functions
    /// emulator only routes callables under its own project id, and the Auth
    /// emulator maps every API-key request to it, so the app must not carry the
    /// production project id from the plist while it talks to the emulators.
    static let demoProject = "demo-pubdates"

    /// Replaces `FirebaseApp.configure()`: the plist's options, with the project
    /// re-pointed at the demo namespace when the emulators are requested.
    static func configureFirebase() {
        #if DEBUG
        if isEnabled,
           let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path) {
            options.projectID = demoProject
            options.storageBucket = "\(demoProject).appspot.com"
            FirebaseApp.configure(options: options)
            return
        }
        #endif
        FirebaseApp.configure()
    }

    /// Call right after `configureFirebase()`, before any service is touched.
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
