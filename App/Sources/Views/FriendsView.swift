import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Friend management: incoming requests, the friend list (remove / block /
/// report via context menu), exact-username search + add, and a ShareLink
/// invite. Consumes only `FriendServicing` — never Firebase types.
struct FriendsView: View {
    private let profile: UserProfile
    private let friendService: any FriendServicing

    @State private var requests: [FriendRequest] = []
    @State private var friends: [UserProfile] = []
    @State private var searchText = ""
    @State private var searchStatus: String?
    @State private var isWorking = false
    @State private var errorMessage: String?

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
            .navigationTitle("Friends")
            .task { await reload() }
            .refreshable { await reload() }
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Remove \(removeTarget?.displayName ?? "this friend")?",
                isPresented: $showRemoveDialog,
                titleVisibility: .visible,
                presenting: removeTarget
            ) { friend in
                Button("Remove friend", role: .destructive) { remove(friend) }
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
                Text("Blocking ends your friendship and hides your beers from each other. They won't be notified.")
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

    // MARK: - Sections

    private var addFriendSection: some View {
        Section("Add a friend") {
            HStack {
                TextField("Exact username", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                Button {
                    addFriend()
                } label: {
                    if isWorking {
                        ProgressView()
                    } else {
                        Image(systemName: "person.badge.plus")
                    }
                }
                .disabled(isWorking || searchText.isEmpty)
                .accessibilityLabel("Send friend request")
            }
            if let searchStatus {
                Text(searchStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var requestsSection: some View {
        Section("Requests") {
            ForEach(requests) { request in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(request.fromDisplayName)
                            .font(.headline)
                        Text("@\(request.fromUsername)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        accept(request)
                    } label: {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .accessibilityLabel("Accept \(request.fromDisplayName)")
                    Button {
                        decline(request)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("Decline \(request.fromDisplayName)")
                }
                // Borderless so both buttons stay independently tappable in a List row.
                .buttonStyle(.borderless)
            }
        }
    }

    private var friendsSection: some View {
        Section("Friends") {
            if friends.isEmpty {
                Text("No friends yet — beers taste better shared. 🍻")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(friends) { friend in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.displayName)
                                .font(.headline)
                            Text("@\(friend.username)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(friend.beerCount) 🍺")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contextMenu {
                        Button {
                            removeTarget = friend
                            showRemoveDialog = true
                        } label: {
                            Label("Remove friend", systemImage: "person.badge.minus")
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
            }
        }
    }

    private var inviteSection: some View {
        Section {
            ShareLink(item: "Add me on Pints With Mates! My username is @\(profile.username) 🍺") {
                Label("Invite a friend", systemImage: "square.and.arrow.up")
            }
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
            errorMessage = "Couldn't load your friends — pull to retry."
        }
    }

    private func reloadFriends() async {
        do {
            friends = try await friendService.friends()
        } catch {
            errorMessage = "Couldn't load your friends — pull to retry."
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
                    searchStatus = "You're already friends with @\(found.username)."
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
                requests.removeAll { $0.id == request.id }
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
                requests.removeAll { $0.id == request.id }
            } catch {
                errorMessage = "Couldn't decline the request — try again."
            }
        }
    }

    private func remove(_ friend: UserProfile) {
        Task {
            do {
                try await friendService.removeFriend(uid: friend.id)
                friends.removeAll { $0.id == friend.id }
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
                friends.removeAll { $0.id == friend.id }
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
