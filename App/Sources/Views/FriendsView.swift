import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Mates: incoming requests, the mate list (remove / block / report via swipe
/// actions and context menu), exact-username search + add, and a ShareLink
/// invite. Consumes only `FriendServicing` — never Firebase types.
///
/// Design: docs/design/direction.md screen 5 — inset grouped sections, avatar
/// initials on amber, one accent carrying the primary pills, system everything
/// else.
struct FriendsView: View {
    private let profile: UserProfile
    private let friendService: any FriendServicing

    @State private var requests: [FriendRequest] = []
    @State private var friends: [UserProfile] = []
    @State private var searchText = ""
    @State private var searchStatus: String?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showQRSheet = false
    /// The `pubdates://add/<username>` deep link lands in AppState.pendingMateUsername;
    /// drained by the `onChange` below into the normal add flow.
    @EnvironmentObject private var appState: AppState

    @State private var removeTarget: UserProfile?
    @State private var showRemoveDialog = false
    @State private var blockTarget: UserProfile?
    @State private var showBlockDialog = false
    @State private var reportTarget: UserProfile?
    @State private var showReportDialog = false

    init(profile: UserProfile, friendService: any FriendServicing) {
        self.profile = profile
        self.friendService = friendService
    }

    var body: some View {
        NavigationStack {
            List {
                addFriendSection
                if !requests.isEmpty {
                    requestsSection
                }
                friendsSection
                inviteSection
            }
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Mates")
            .navigationBarTitleDisplayMode(.large)
            .task { await reload() }
            .refreshable { await reload() }
            .sheet(isPresented: $showQRSheet) {
                QRMateView(profile: profile) { username in
                    // Same flow as typing the name: search, then send.
                    showQRSheet = false
                    searchText = username
                    addFriend()
                }
                .presentationDetents([.large])
            }
            .onAppear { consumePendingMateLink() }
            .onChange(of: appState.pendingMateUsername) { _, _ in consumePendingMateLink() }
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Remove \(removeTarget?.displayName ?? "this mate")?",
                isPresented: $showRemoveDialog,
                titleVisibility: .visible,
                presenting: removeTarget
            ) { friend in
                Button("Remove mate", role: .destructive) { remove(friend) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You'll stop seeing each other's beers. You can add each other again later.")
            }
            .confirmationDialog(
                "Block \(blockTarget?.displayName ?? "this user")?",
                isPresented: $showBlockDialog,
                titleVisibility: .visible,
                presenting: blockTarget
            ) { friend in
                Button("Block @\(friend.username)", role: .destructive) { block(friend) }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Blocking drops them as a mate and hides your beers from each other. They won't be notified.")
            }
            .confirmationDialog(
                "Report @\(reportTarget?.username ?? "")",
                isPresented: $showReportDialog,
                titleVisibility: .visible,
                presenting: reportTarget
            ) { friend in
                ForEach(HomeView.reportReasons, id: \.self) { reason in
                    Button(reason) { report(friend, reason: reason) }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Add a mate

    private var addFriendSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    searchField
                    addButton
                }
                qrButton
                if let searchStatus {
                    Text(searchStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .animation(Theme.quick, value: searchStatus)
        } header: {
            Eyebrow(text: "Add a mate")
        }
    }

    /// A bare field in the grouped cell — no nested box. The magnifying glass
    /// sits in front of it the way a `Label` icon would.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Add by exact username", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .submitLabel(.done)
                .onSubmit {
                    if !isWorking, !searchText.isEmpty { addFriend() }
                }
                .accessibilityLabel("Mate's exact username")
                .accessibilityIdentifier("friends.search")
        }
        .frame(minHeight: 44)
    }

    private var addButton: some View {
        // The custom pill style can't read `isEnabled`, so the disabled look is
        // chosen here: the quiet emphasis, never amber at half strength.
        let canAdd = !isWorking && !searchText.isEmpty
        return Button {
            addFriend()
        } label: {
            Text("Add")
                .opacity(isWorking ? 0 : 1)
                .overlay {
                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.secondary)  // spinner only shows while quiet
                    }
                }
                .frame(minHeight: 44)
        }
        .buttonStyle(PillButtonStyle(emphasis: canAdd ? .filled : .quiet))
        .disabled(!canAdd)
        .animation(Theme.quick, value: canAdd)
        .accessibilityLabel("Send mate request")
        .accessibilityIdentifier("friends.add")
    }

    /// The face-to-face route into the same flow: show your code or scan a
    /// mate's, instead of spelling a username out loud.
    private var qrButton: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.light()
                showQRSheet = true
            } label: {
                Label("Add with QR", systemImage: "qrcode")
                    .frame(minHeight: 44)
            }
            .buttonStyle(PillButtonStyle(emphasis: .tinted))
            .accessibilityLabel("Add with QR code")
            .accessibilityHint("Shows your code, or scans a mate's")
            .accessibilityIdentifier("friends.qr")
            Spacer(minLength: 0)
        }
    }

    // MARK: - Requests

    private var requestsSection: some View {
        Section {
            ForEach(requests) { request in
                requestRow(request)
            }
        } header: {
            Eyebrow(text: "Requests")
        }
    }

    private func requestRow(_ request: FriendRequest) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: request.fromDisplayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("@\(request.fromUsername)")
                    .font(.headline)
                Text(request.fromDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button("Accept") { accept(request) }
                    .buttonStyle(PillButtonStyle(emphasis: .filled))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Accept \(request.fromDisplayName)")
                Button("Decline") { decline(request) }
                    .buttonStyle(PillButtonStyle(emphasis: .quiet))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel("Decline \(request.fromDisplayName)")
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Mates

    private var friendsSection: some View {
        Section {
            if friends.isEmpty {
                Text("No mates yet. Add one above or send an invite.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(friends) { friend in
                    friendRow(friend)
                }
            }
        } header: {
            Eyebrow(text: "Mates")
        }
    }

    private func friendRow(_ friend: UserProfile) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: friend.displayName, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.displayName)
                    .font(.headline)
                Text("@\(friend.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        // Swipe actions and the context menu carry the same destructive pair;
        // VoiceOver surfaces both as custom actions on the row.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                removeTarget = friend
                showRemoveDialog = true
            } label: {
                Label("Remove", systemImage: "person.badge.minus")
            }
            Button {
                blockTarget = friend
                showBlockDialog = true
            } label: {
                Label("Block", systemImage: "hand.raised")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                removeTarget = friend
                showRemoveDialog = true
            } label: {
                Label("Remove mate", systemImage: "person.badge.minus")
            }
            Button {
                reportTarget = friend
                showReportDialog = true
            } label: {
                Label("Report", systemImage: "exclamationmark.bubble")
            }
            Button(role: .destructive) {
                blockTarget = friend
                showBlockDialog = true
            } label: {
                Label("Block", systemImage: "hand.raised")
            }
        }
    }

    // MARK: - Invite

    private var inviteSection: some View {
        Section {
            ShareLink(item: "Add me on PubDates! My username is @\(profile.username) 🍺") {
                Label("Invite a mate", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(PillButtonStyle(emphasis: .tinted))
            .accessibilityLabel("Invite a mate")
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions

    private func reload() async {
        do {
            async let requestsTask = friendService.incomingRequests()
            async let friendsTask = friendService.friends()
            let (loadedRequests, loadedFriends) = try await (requestsTask, friendsTask)
            requests = loadedRequests
            friends = loadedFriends
        } catch {
            errorMessage = "Couldn't load your mates — pull to retry."
        }
    }

    /// `pubdates://add/<username>`: AppState holds the name until this screen exists.
    private func consumePendingMateLink() {
        guard let username = appState.pendingMateUsername else { return }
        appState.pendingMateUsername = nil
        showQRSheet = false
        searchText = username
        addFriend()
    }

    private func reloadFriends() async {
        do {
            friends = try await friendService.friends()
        } catch {
            errorMessage = "Couldn't load your mates — pull to retry."
        }
    }

    private func addFriend() {
        let raw = searchText
        searchStatus = nil
        guard let username = Username.normalize(raw) else {
            searchStatus = "That's not a valid username (3–15 chars: a–z, 0–9, _)."
            return
        }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                guard let found = try await friendService.searchUser(username: username) else {
                    searchStatus = "No one named @\(username) — usernames must match exactly."
                    return
                }
                if found.id == profile.id {
                    searchStatus = "That's you! 🍺"
                    return
                }
                if friends.contains(where: { $0.id == found.id }) {
                    searchStatus = "You're already mates with @\(found.username)."
                    return
                }
                try await friendService.sendRequest(to: found.id)
                searchStatus = "Request sent to @\(found.username) 🍻"
                searchText = ""
            } catch {
                searchStatus = "Couldn't send the request — try again."
            }
        }
    }

    private func accept(_ request: FriendRequest) {
        Task {
            do {
                try await friendService.accept(request)
                Haptics.success()
                withAnimation(Theme.spring) {
                    requests.removeAll { $0.id == request.id }
                }
                // Refresh friends only: the server trigger deletes the request doc
                // a moment later, so re-reading requests now would resurrect it.
                await reloadFriends()
            } catch {
                errorMessage = "Couldn't accept the request — try again."
            }
        }
    }

    private func decline(_ request: FriendRequest) {
        Task {
            do {
                try await friendService.decline(request)
                withAnimation(Theme.spring) {
                    requests.removeAll { $0.id == request.id }
                }
            } catch {
                errorMessage = "Couldn't decline the request — try again."
            }
        }
    }

    private func remove(_ friend: UserProfile) {
        Task {
            do {
                try await friendService.removeFriend(uid: friend.id)
                withAnimation(Theme.spring) {
                    friends.removeAll { $0.id == friend.id }
                }
            } catch {
                errorMessage = "Couldn't remove @\(friend.username) — try again."
            }
        }
    }

    private func block(_ friend: UserProfile) {
        Task {
            do {
                // Only writes the block doc; the server severs the friendship.
                try await friendService.block(uid: friend.id)
                withAnimation(Theme.spring) {
                    friends.removeAll { $0.id == friend.id }
                }
            } catch {
                errorMessage = "Couldn't block @\(friend.username) — try again."
            }
        }
    }

    private func report(_ friend: UserProfile, reason: String) {
        Task {
            do {
                try await friendService.report(beerId: nil, uid: friend.id, reason: reason)
                searchStatus = nil
                errorMessage = nil
            } catch {
                errorMessage = "Couldn't send your report — try again."
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
