import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// The main screen: one big log button, a camera shortcut, and the live feed.
/// Consumes ONLY BeerKit (`HomeViewModel`, protocols) — never Firebase types;
/// the screenshot reporter closure is injected pre-wired by RootView.
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase

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
            VStack(spacing: 12) {
                logButtons
                feedList
            }
            .navigationTitle("BeerWithMe")
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        .task(id: feedEpoch) {
            if feedEpoch > 0 {
                // Restart: .task(id:) just cancelled the previous stream — give it
                // a beat to unwind so start()'s internal isObserving guard is clear.
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
            }
            await viewModel.start()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Feed staleness mitigation: coming back from background restarts the
            // stream, re-snapshotting the friend list.
            if newPhase == .active, oldPhase == .background {
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
                screenshotReporter: screenshotReporter,
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

    // MARK: - Log buttons

    private var logButtons: some View {
        HStack(spacing: 12) {
            Button {
                Task { await viewModel.logBeer(photoJPEG: nil) }
            } label: {
                Text("🍺 I'm drinking a beer")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)

            Button {
                showCamera = true
            } label: {
                Image(systemName: "camera.fill")
                    .font(.title3)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Log a beer with a photo")
        }
        .disabled(viewModel.isLogging)
        .padding(.horizontal)
    }

    // MARK: - Feed

    @ViewBuilder
    private var feedList: some View {
        if viewModel.feed.isEmpty {
            ContentUnavailableView(
                "No beers yet",
                systemImage: "mug",
                description: Text("Log one above, or add friends to see theirs.")
            )
            .frame(maxHeight: .infinity)
        } else {
            List(viewModel.feed) { beer in
                feedRow(beer)
            }
            .listStyle(.plain)
            .refreshable {
                feedEpoch += 1
            }
        }
    }

    private func feedRow(_ beer: BeerLog) -> some View {
        let isMine = beer.ownerUid == profile.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isMine ? "You" : beer.ownerName)
                    .font(.headline)
                Text(beer.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            photoChip(for: beer)
            cheersButton(for: beer, isMine: isMine)
        }
        .padding(.vertical, 4)
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
                Text("📸 view once")
                    .font(.caption.bold())
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        case .seen:
            Text("Seen")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        case .none, .expired:
            EmptyView()
        }
    }

    private func cheersButton(for beer: BeerLog, isMine: Bool) -> some View {
        Button {
            Task { await viewModel.cheers(beer) }
        } label: {
            HStack(spacing: 4) {
                Text("🍻")
                Text("\(beer.cheersCount)")
                    .font(.subheadline.monospacedDigit())
            }
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .disabled(isMine || viewModel.cheersedBeerIds.contains(beer.id))
        .accessibilityLabel("Cheers, \(beer.cheersCount) so far")
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
