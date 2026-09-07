import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// The main screen: one big log button, a camera shortcut, and the live feed.
/// Consumes ONLY BeerKit (`HomeViewModel`, protocols) — never Firebase types;
/// the screenshot reporter closure is injected pre-wired by RootView.
///
/// Layout follows docs/design/direction.md: large title "PubDates" collapsing on
/// scroll, the amber hero + round camera button directly under it (both inside
/// the scroll view, so the title collapses natively), then the last 24 hours of
/// beers as plain rows.
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let profile: UserProfile
    private let friendService: any FriendServicing
    private let screenshotReporter: @Sendable (String) async -> Void

    @State private var showCamera = false
    @State private var photoViewer: PhotoViewerItem?
    /// Bumped to restart the feed stream (scene re-activation, pull-to-refresh):
    /// `observeFeed()` snapshots the friend list at subscribe time, so a restart
    /// is how new friends' beers show up (parked v1 limitation, Task 9 note).
    @State private var feedEpoch = 0
    @State private var reportTarget: BeerLog?
    @State private var showReportDialog = false
    @State private var blockTarget: BeerLog?
    @State private var showBlockDialog = false
    @State private var infoMessage: String?

    static let reportReasons = ["Not a beer 🚨", "Inappropriate photo", "Harassment", "Other"]

    init(
        profile: UserProfile,
        beerService: any BeerServicing,
        friendService: any FriendServicing,
        screenshotReporter: @escaping @Sendable (String) async -> Void
    ) {
        self.profile = profile
        self.friendService = friendService
        self.screenshotReporter = screenshotReporter
        _viewModel = StateObject(wrappedValue: HomeViewModel(service: beerService))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    heroRow
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 20, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if viewModel.feed.isEmpty {
                    Section {
                        emptyState
                            .listRowInsets(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    Section {
                        ForEach(viewModel.feed) { beer in
                            feedRow(beer)
                        }
                    } header: {
                        Eyebrow(text: "Last 24 hours")
                            .textCase(nil)
                            .padding(.vertical, 2)
                    }
                }
            }
            .listStyle(.plain)
            .listSectionSeparator(.hidden)
            // Pull-to-refresh works on the empty state too: the hero row keeps
            // the list scrollable even with no beers.
            .refreshable {
                feedEpoch += 1
            }
            // Signature interaction: a new row springs in at the top. Reduce
            // Motion downgrades it to a crossfade.
            .animation(reduceMotion ? Theme.quick : Theme.spring, value: viewModel.feed.map(\.id))
            .navigationTitle("PubDates")
            .navigationBarTitleDisplayMode(.large)
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        // Changing the id cancels the previous start(); the new one awaits the old
        // stream's teardown itself, so no sleep is needed here.
        .task(id: feedEpoch) {
            await viewModel.start()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Coming back to the foreground restarts the stream (re-snapshots the
            // friend list). iOS goes background → inactive → active, so compare
            // against anything-but-active rather than `.background`.
            if newPhase == .active, oldPhase != .active {
                feedEpoch += 1
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { data in
                Task { await viewModel.logBeer(photoJPEG: data) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $photoViewer) { item in
            PhotoViewerView(
                url: item.url,
                ownerName: item.ownerName,
                beerId: item.id,
                // Explicit @Sendable wrapper: passing the stored property through
                // the SwiftUI content closure drops the attribute (compiler warning).
                screenshotReporter: { [screenshotReporter] id in await screenshotReporter(id) },
                onDismiss: { photoViewer = nil }
            )
        }
        .confirmationDialog(
            "Report this beer",
            isPresented: $showReportDialog,
            titleVisibility: .visible,
            presenting: reportTarget
        ) { beer in
            ForEach(Self.reportReasons, id: \.self) { reason in
                Button(reason) { submitReport(beer: beer, reason: reason) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Block \(blockTarget?.ownerName ?? "this user")?",
            isPresented: $showBlockDialog,
            titleVisibility: .visible,
            presenting: blockTarget
        ) { beer in
            Button("Block \(beer.ownerName)", role: .destructive) {
                submitBlock(uid: beer.ownerUid, name: beer.ownerName)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Blocking ends your friendship and hides your beers from each other. They won't be notified.")
        }
        // On its own node (the outer stack) — a second .alert on the same view
        // as the error alert would collide; separate nodes both work.
        .alert("🍻", isPresented: infoBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
    }

    // MARK: - Hero

    /// One button owns the screen: full-width amber log button with the camera
    /// shortcut to its right. Both are disabled while a photo uploads.
    private var heroRow: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.success()
                Task { await viewModel.logBeer(photoJPEG: nil) }
            } label: {
                Text("🍺 I'm having a beer")
            }
            .buttonStyle(HeroButtonStyle(isBusy: viewModel.isUploadingPhoto))
            .accessibilityLabel("I'm having a beer")
            .accessibilityHint("Tells your mates you cracked one open")
            .accessibilityIdentifier("home.log")

            Button {
                Haptics.light()
                showCamera = true
            } label: {
                Image(systemName: "camera.fill")
            }
            .buttonStyle(RoundIconButtonStyle())
            .accessibilityLabel("Log a beer with a photo")
            .accessibilityIdentifier("home.camera")
        }
        .disabled(viewModel.isUploadingPhoto)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No beers yet")
                .font(.title3.weight(.semibold))
            Text("Tap the button when you crack one open — your mates will hear it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                Haptics.light()
                NotificationCenter.default.post(name: .pubDatesSwitchToFriends, object: nil)
            } label: {
                Text("Add a mate")
            }
            .buttonStyle(PillButtonStyle(emphasis: .tinted))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Add a mate")
            .accessibilityHint("Opens the Friends tab")
            .accessibilityIdentifier("home.addMate")
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Feed

    private func feedRow(_ beer: BeerLog) -> some View {
        let isMine = beer.ownerUid == profile.id
        return HStack(spacing: 12) {
            AvatarView(name: isMine ? profile.displayName : beer.ownerName, size: 52)

            VStack(alignment: .leading, spacing: 2) {
                // "You" stays a standalone static text — the UI test looks for it.
                Text(isMine ? "You" : beer.ownerName)
                    .font(.headline)
                    .lineLimit(1)
                Text(beer.createdAt, style: .relative)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            photoChip(for: beer)
            cheersButton(for: beer, isMine: isMine)
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isMine {
                Button(role: .destructive) {
                    blockTarget = beer
                    showBlockDialog = true
                } label: {
                    Label("Block", systemImage: "hand.raised")
                }
                Button {
                    reportTarget = beer
                    showReportDialog = true
                } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }
                .tint(Theme.accent)
            }
        }
        .contextMenu {
            if !isMine {
                Button {
                    reportTarget = beer
                    showReportDialog = true
                } label: {
                    Label("Report", systemImage: "exclamationmark.bubble")
                }
                Button(role: .destructive) {
                    blockTarget = beer
                    showBlockDialog = true
                } label: {
                    Label("Block \(beer.ownerName)", systemImage: "hand.raised")
                }
            }
        }
    }

    @ViewBuilder
    private func photoChip(for beer: BeerLog) -> some View {
        switch beer.photoChipState(viewedByMe: viewModel.viewedBeerIds.contains(beer.id), now: Date()) {
        case .sealed:
            Button {
                openPhoto(beer)
            } label: {
                Text("📸 View once")
            }
            .buttonStyle(PillButtonStyle(emphasis: .filled))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("View photo once")
            .accessibilityHint("You can only look at this photo one time")
        case .seen:
            StatusPill(text: "Seen")
                .accessibilityLabel("Photo already seen")
        case .none, .expired:
            EmptyView()
        }
    }

    private func cheersButton(for beer: BeerLog, isMine: Bool) -> some View {
        let alreadyCheersed = viewModel.cheersedBeerIds.contains(beer.id)
        let isDisabled = isMine || alreadyCheersed
        return Button {
            Haptics.light()
            Task { await viewModel.cheers(beer) }
        } label: {
            HStack(spacing: 4) {
                Text("🍻")
                Text("\(beer.cheersCount)")
                    .monospacedDigit()
            }
        }
        .buttonStyle(PillButtonStyle(emphasis: isDisabled ? .quiet : .tinted))
        .disabled(isDisabled)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(
            isDisabled
                ? "Cheersed, \(beer.cheersCount) so far"
                : "Cheers, \(beer.cheersCount) so far"
        )
    }

    // MARK: - Actions

    private func openPhoto(_ beer: BeerLog) {
        Task {
            // nil → openPhoto already set viewModel.errorMessage (alert shows).
            if let url = await viewModel.openPhoto(beer) {
                photoViewer = PhotoViewerItem(
                    id: beer.id,
                    url: url,
                    ownerName: beer.ownerUid == profile.id ? "You" : beer.ownerName
                )
            }
        }
    }

    private func submitReport(beer: BeerLog, reason: String) {
        Task {
            do {
                try await friendService.report(beerId: beer.id, uid: beer.ownerUid, reason: reason)
                infoMessage = "Thanks — we'll take a look."
            } catch {
                viewModel.errorMessage = "Couldn't send your report — try again."
            }
        }
    }

    private func submitBlock(uid: String, name: String) {
        Task {
            do {
                // Only writes the block doc; the server severs the friendship.
                try await friendService.block(uid: uid)
                infoMessage = "\(name) is blocked."
                feedEpoch += 1 // restart the stream so their beers drop out
            } catch {
                viewModel.errorMessage = "Couldn't block — try again."
            }
        }
    }

    // MARK: - Bindings

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private var infoBinding: Binding<Bool> {
        Binding(
            get: { infoMessage != nil },
            set: { if !$0 { infoMessage = nil } }
        )
    }
}

/// Identifiable payload for the photo-viewer fullScreenCover.
private struct PhotoViewerItem: Identifiable {
    let id: String // beerId
    let url: URL
    let ownerName: String
}

extension Notification.Name {
    /// Posted by the Home empty state's "Add a mate" button; the app shell
    /// observes it and selects the Friends tab (wiring lands with the shell).
    static let pubDatesSwitchToFriends = Notification.Name("pubDatesSwitchToFriends")
}
