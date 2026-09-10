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

    /// The handle shown in the header. `profile` is a `let`, and a successful
    /// change re-keys the whole session through `AppState.becomeReady` — this
    /// shows the new name straight away instead of waiting for that rebuild to
    /// reach us. Kept in step with the profile in case it changes elsewhere.
    @State private var shownUsername: String
    @State private var showChangeUsername = false
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

    init(profile: UserProfile) {
        self.profile = profile
        _shownUsername = State(initialValue: profile.username)
    }

    private var concreteFriendService: FirebaseFriendService? {
        appState.friendService as? FirebaseFriendService
    }

    var body: some View {
        NavigationStack {
            List {
                profileSection
                accountDetailsSection
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
            // A rebuild with a different profile (another device changed the
            // handle) wins over the locally shown one.
            .onChange(of: profile.username) { _, newValue in
                shownUsername = newValue
            }
            .sheet(isPresented: $showChangeUsername) {
                ChangeUsernameSheet(currentUsername: shownUsername) { newUsername in
                    shownUsername = newUsername
                }
            }
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
    /// the header *is* the profile. Identity only — changing the username is a
    /// list row below, not a control in here.
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
                    Text("@\(shownUsername)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                StatusPill(text: drinkCountText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            // Nothing tappable in here any more, so the whole header can read as
            // one VoiceOver element.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(profile.displayName), @\(shownUsername), \(drinkCountText)")
        }
    }

    /// An editable account field is a list row on iOS: label, current value,
    /// chevron. `.plain` keeps the row's own colours (primary label, secondary
    /// value) instead of painting the whole thing in the list's amber tint.
    private var accountDetailsSection: some View {
        Section("Account details") {
            Button {
                showChangeUsername = true
            } label: {
                HStack(spacing: 8) {
                    LabeledContent("Username", value: "@\(shownUsername)")
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .accessibilityIdentifier("settings.changeUsername")
            .accessibilityLabel("Username")
            .accessibilityValue("@\(shownUsername)")
            .accessibilityHint("Change your username")
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
            Text("The bar's name and its map position go with your drink, never your own location. Mates only, in the feed and on the Map.")
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

    /// "N drinks logged" — the logged thing is a drink (PRODUCT.md terminology).
    private var drinkCountText: String {
        let n = profile.beerCount
        return "\(n) drink\(n == 1 ? "" : "s") logged"
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

// MARK: - Change username

/// One field, the same debounced availability copy as onboarding, one hero
/// Save. Errors that only the server knows ("taken", "once a day") come back
/// through `AppState.errorMessage` and are shown here, on the sheet, so the
/// sheet can stay open and the user can try another name.
private struct ChangeUsernameSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Used only to recognise "that's you already" while typing.
    let currentUsername: String
    /// Called with the new (normalized) username after a successful save.
    let onSaved: (String) -> Void

    @State private var username = ""
    @State private var availability: Availability = .idle
    @State private var isSaving = false
    @State private var alertMessage: String?

    private enum Availability: Equatable {
        case idle          // empty field
        case invalid       // fails Username.normalize
        case checking
        case available
        case taken
        case mine          // the name you already have
        case unknown       // availability lookup failed (offline etc.)
    }

    private var canSave: Bool {
        !isSaving && (availability == .available || availability == .unknown)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("New username")
                    .font(Theme.displayTitle2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 10) {
                    fieldSurface {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            TextField("username", text: $username)
                                .accessibilityIdentifier("settings.newUsername")
                                .accessibilityLabel("New username")
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                                .submitLabel(.done)
                                .disabled(isSaving)
                        }
                    }
                    availabilityLabel
                        .animation(Theme.quick, value: availability)
                }

                Text("Mates find you by exact username. You can change it once a day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    Haptics.light()
                    save()
                } label: {
                    if isSaving {
                        ProgressView()
                            .tint(Theme.onAccent)
                    } else {
                        Text("Save")
                    }
                }
                .buttonStyle(HeroButtonStyle())
                .accessibilityIdentifier("settings.saveUsername")
                .accessibilityLabel("Save")
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
                .animation(Theme.quick, value: canSave)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.ground.ignoresSafeArea())
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        // Debounced live availability: retyping changes the id, which cancels the
        // in-flight check (including its sleep) and starts a new one.
        .task(id: username) {
            await checkAvailability()
        }
        .alert("Oops", isPresented: alertBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    /// Rounded card that holds a text field (Theme.surface, cardRadius).
    private func fieldSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
            )
    }

    @ViewBuilder
    private var availabilityLabel: some View {
        Group {
            switch availability {
            case .idle:
                Text("3–15 characters: a–z, 0–9, _ — starts with a letter.")
                    .foregroundStyle(.secondary)
            case .invalid:
                Label("3–15 characters: a–z, 0–9, _ — starts with a letter.", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            case .available:
                Label("Available 🍻", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .taken:
                Label("Taken — try another.", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case .mine:
                Label("That's you already.", systemImage: "person.crop.circle")
                    .foregroundStyle(.secondary)
            case .unknown:
                Label("Couldn't check availability — you can still try to save it.", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func checkAvailability() async {
        guard !username.isEmpty else {
            availability = .idle
            return
        }
        guard let normalized = Username.normalize(username) else {
            availability = .invalid
            return
        }
        // Your own name is reserved by you, so the lookup would say "taken".
        guard normalized != currentUsername else {
            availability = .mine
            return
        }
        availability = .checking
        try? await Task.sleep(for: .milliseconds(400)) // debounce window
        guard !Task.isCancelled else { return }
        let taken = await appState.isUsernameTaken(normalized)
        guard !Task.isCancelled else { return }
        switch taken {
        case .some(true): availability = .taken
        case .some(false): availability = .available
        case .none: availability = .unknown
        }
    }

    private func save() {
        let typed = username
        isSaving = true
        Task {
            // AppState normalizes, calls the server and re-keys the session on
            // success; on failure it left the reason in `errorMessage`.
            let ok = await appState.changeUsername(typed)
            isSaving = false
            if ok {
                Haptics.success()
                onSaved(Username.normalize(typed) ?? typed)
                dismiss()
            } else {
                // The reason (taken / once a day / offline) is only known here, and
                // the sheet stays open so it can be read and acted on.
                alertMessage = appState.errorMessage ?? "Couldn't change your username — try again."
                appState.errorMessage = nil
            }
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )
    }
}
