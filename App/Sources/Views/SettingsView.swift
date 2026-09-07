import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Profile, blocked-user management, sign out, delete account (double
/// confirmation), privacy policy link, version footer.
///
/// Blocked-list + unblock are NOT on the frozen `FriendServicing` protocol —
/// they live as extra methods on the concrete `FirebaseFriendService`, reached
/// by downcasting `appState.friendService` (see Task 10 plan note).
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    let profile: UserProfile

    @State private var blockedUsers: [BlockedUser] = []
    @State private var blockedUnavailable = false
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false
    @State private var showDeleteFinalConfirm = false
    @State private var errorMessage: String?

    // Placeholder until Task 11/12 publish the real policy URL.
    private let privacyPolicyURL = URL(string: "https://example.com/beerwithme/privacy")!

    private var concreteFriendService: FirebaseFriendService? {
        appState.friendService as? FirebaseFriendService
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                blockedSection
                aboutSection
                accountSection
                versionFooterSection
            }
            .navigationTitle("Settings")
            .task { await loadBlocked() }
            .refreshable { await loadBlocked() }
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Delete your account?", isPresented: $showDeleteConfirm) {
                Button("Continue", role: .destructive) { showDeleteFinalConfirm = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can't undo this.")
            }
            .alert("Last call — are you sure?", isPresented: $showDeleteFinalConfirm) {
                Button("Delete everything", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your beers, photos and friendships.")
            }
        }
    }

    // MARK: - Sections

    private var profileSection: some View {
        Section("Profile") {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.headline)
                Text("@\(profile.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("Beers logged", value: "\(profile.beerCount) 🍺")
        }
    }

    private var blockedSection: some View {
        Section("Blocked users") {
            if blockedUnavailable {
                Text("Blocked-user management isn't available right now.")
                    .foregroundStyle(.secondary)
            } else if blockedUsers.isEmpty {
                Text("You haven't blocked anyone. 🍻")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(blockedUsers) { blocked in
                    HStack {
                        Text(blocked.username.map { "@\($0)" } ?? "Deleted user")
                        Spacer()
                        Button("Unblock") { unblock(blocked) }
                            .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    private var aboutSection: some View {
        Section {
            Link(destination: privacyPolicyURL) {
                Label("Privacy policy", systemImage: "hand.raised.circle")
            }
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Button("Sign out") {
                Task { await appState.signOut() }
            }
            .disabled(isDeleting)
            Button("Delete account", role: .destructive) {
                showDeleteConfirm = true
            }
            .disabled(isDeleting)
        }
    }

    private var versionFooterSection: some View {
        Section {
        } footer: {
            Text(Self.versionString)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private static var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "PubDates \(version) (\(build)) 🍺"
    }

    // MARK: - Actions

    private func loadBlocked() async {
        guard let service = concreteFriendService else {
            // Only possible if AppState is ever wired to a non-Firebase
            // FriendServicing — the frozen protocol has no blocked-list API.
            blockedUnavailable = true
            return
        }
        blockedUnavailable = false
        do {
            blockedUsers = try await service.blockedUsers()
        } catch {
            errorMessage = "Couldn't load your blocked list — pull to retry."
        }
    }

    private func unblock(_ blocked: BlockedUser) {
        guard let service = concreteFriendService else { return }
        Task {
            do {
                try await service.unblock(uid: blocked.id)
                blockedUsers.removeAll { $0.id == blocked.id }
            } catch {
                errorMessage = "Couldn't unblock — try again."
            }
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task {
            // On success the auth listener flips phase to .signedOut; on failure
            // AppState sets its own errorMessage — mirror it here so it's visible.
            await appState.deleteAccount()
            isDeleting = false
            if let message = appState.errorMessage {
                errorMessage = message
                appState.errorMessage = nil
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
