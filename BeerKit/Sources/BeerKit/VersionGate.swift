import Foundation

/// Whether this build is still allowed to run. TestFlight cannot force an
/// update, so the app asks the server for a floor and refuses to go below it
/// (Tim, 2026-10-04: "can we force people to upgrade?"). Used when a change
/// only works if everyone is on it — the location requirement, say.
public enum VersionGate {
    /// Build numbers are the CI run number: plain increasing integers.
    /// Unparseable or missing config means "allowed": a gate that fails closed
    /// would brick every phone the moment the config read fails.
    public static func isSupported(build: String?, minimum: Int?) -> Bool {
        guard let minimum else { return true }
        guard let build, let number = Int(build.split(separator: ".").first.map(String.init) ?? build)
        else { return true }
        return number >= minimum
    }
}
