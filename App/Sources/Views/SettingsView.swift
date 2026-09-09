import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Profile, blocked-user management, sign out, delete account (double
/// confirmation), privacy policy link, version footer.
///
/// Screen 6 of docs/design/direction.md: inset grouped list, a profile header
/// with the big amber initial, then quiet Blocked / About / Account groups.
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
    /// Opt-in place naming. The same key `LocationPlaceProvider` reads before it
    /// ever touches Core Location, so this switch alone decides.
    @AppStorage("sharePlace") private var sharePlace = false

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
                privacySection
                aboutSection
                accountSection
                versionFooterSection
            }
            .listStyle(.insetGrouped)
            .tint(Theme.accentInk)  // tint colours words and glyphs; fills use Theme.accent
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
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

    /// Big amber initial, name, @username and one quiet stat. No section header:
    /// the header *is* the profile.
    private var profileSection: some View {
        Section {
            VStack(spacing: 12) {
                AvatarView(name: profile.displayName, size: 72)
                VStack(spacing: 2) {
                    Text(profile.displayName)
                        .font(Theme.displayTitle2)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                StatusPill(text: beerCountText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(profile.displayName), @\(profile.username), \(beerCountText)")
        }
    }

    private var blockedSection: some View {
        Section("Blocked") {
            if blockedUnavailable {
                Text("Blocked-user management isn't available right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if blockedUsers.isEmpty {
                Text("You haven't blocked anyone. 🍻")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(blockedUsers) { blocked in
                    blockedRow(blocked)
                }
            }
        }
    }

    private func blockedRow(_ blocked: BlockedUser) -> some View {
        // A deleted account keeps its block; the empty name falls back to the
        // 🍺 glyph inside AvatarView.
        HStack(spacing: 12) {
            AvatarView(name: blocked.username ?? "", size: 36)
            if let username = blocked.username {
                Text("@\(username)")
                    .font(.body)
            } else {
                Text("Deleted user")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Unblock") { unblock(blocked) }
                .buttonStyle(PillButtonStyle(emphasis: .tinted))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel(blocked.username.map { "Unblock @\($0)" } ?? "Unblock deleted user")
        }
        .padding(.vertical, 2)
    }

    /// One switch, plainly worded: what leaves the phone is a bar name or a city,
    /// and only to your mates.
    private var privacySection: some View {
        Section {
            Toggle("Share where I'm drinking", isOn: $sharePlace)
                // The list tints words with `accentInk`; a switch is a fill.
                .tint(Theme.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.sharePlace")
                .onChange(of: sharePlace) { _, isOn in
                    // Ask here, where the sentence below explains why — not at
                    // tap time on the log button.
                    if isOn { LocationPlaceProvider.shared.requestPermissionIfNeeded() }
                }
        } header: {
            Text("Privacy")
        } footer: {
            Text("Only the name of the bar or the city goes with your beer, never your exact location. Mates only.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            Link(destination: privacyPolicyURL) {
                HStack {
                    Label("Privacy policy", systemImage: "lock.shield")
                    Spacer(minLength: 12)
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Privacy policy")
            .accessibilityHint("Opens in your browser")
        }
    }

    private var accountSection: some View {
        Section("Account") {
            Button {
                Task { await appState.signOut() }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isDeleting)
            .accessibilityIdentifier("settings.signout")

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Label("Delete account", systemImage: "trash")
                    if isDeleting {
                        Spacer(minLength: 12)
                        ProgressView()
                    }
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .disabled(isDeleting)
            .accessibilityIdentifier("settings.delete")
        }
    }

    private var versionFooterSection: some View {
        Section {
        } footer: {
            Text(Self.versionString)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
    }

    private var beerCountText: String {
        "\(profile.beerCount) beer\(profile.beerCount == 1 ? "" : "s") logged"
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
