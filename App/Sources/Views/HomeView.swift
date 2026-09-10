import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// The main screen: the drink picker, a camera shortcut, and the live feed.
/// Consumes ONLY BeerKit (`HomeViewModel`, protocols) — never Firebase types;
/// the screenshot reporter closure is injected pre-wired by RootView.
///
/// Layout follows docs/design/direction.md: large title "PubDates" collapsing on
/// scroll, then the hero — a row of drawn glasses, one tap each, with the round
/// camera button as the row's last cell (all inside the scroll view, so the
/// title collapses natively), then the last 24 hours of drinks as plain rows.
/// Every row carries the glass that was picked, draining as the 24 hours run out.
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
    /// The glass tapped this session; the camera falls back to `lastDrink`.
    @State private var selectedDrink: DrinkKind?
    /// Shared with `DrinkPickerView` (same key): what to pour a photo beer into.
    @AppStorage("lastDrink") private var lastDrink = DrinkKind.pils.rawValue
    /// Anchor for the feed's minute tick. Stable across re-renders, unlike a
    /// fresh `.now` in the body, so the schedule never restarts.
    @State private var glassClock = Date()

    static let reportReasons = ["Not a drink 🚨", "Inappropriate photo", "Harassment", "Other"]

    init(
        profile: UserProfile,
        beerService: any BeerServicing,
        friendService: any FriendServicing,
        screenshotReporter: @escaping @Sendable (String) async -> Void
    ) {
        self.profile = profile
        self.friendService = friendService
        self.screenshotReporter = screenshotReporter
        // The place provider is wired here, not in the app shell: it is a phone
        // capability (Core Location), not an injected service, and it no-ops
        // unless the user turned "Share where I'm drinking" on in Settings.
        _viewModel = StateObject(wrappedValue: HomeViewModel(
            service: beerService,
            placeProvider: LocationPlaceProvider.shared
        ))
    }

    var body: some View {
        NavigationStack {
            // The reader only measures the viewport, so the empty state can claim
            // half of it and sit in the middle of what's left under the hero.
            GeometryReader { proxy in
                // The glasses on the rows drain over the 24 hours: one tick a
                // minute re-renders their levels (and retires an expired photo
                // chip) without a timer of our own.
                TimelineView(.periodic(from: glassClock, by: 60)) { context in
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
                                    .frame(minHeight: max(0, proxy.size.height * 0.5))
                                    .listRowInsets(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                            }
                        } else {
                            // No eyebrow above the feed: the relative time on every row
                            // already says these are the last 24 hours.
                            Section {
                                ForEach(viewModel.feed) { beer in
                                    feedRow(beer, now: context.date)
                                }
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
                }
            }
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
                let drink = selectedDrink ?? DrinkKind(rawValue: lastDrink) ?? .pils
                Task { await viewModel.logBeer(photoJPEG: data, drink: drink) }
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
                onDismiss: {
                    // View-once: the temp file goes with the viewer.
                    try? FileManager.default.removeItem(at: item.url)
                    photoViewer = nil
                }
            )
        }
        .confirmationDialog(
            "Report this drink",
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

    /// The glasses own the screen: pick what you are drinking and it is logged on
    /// the tap that fills the glass (Tim: "je moet selecteren wat voor drankje").
    /// The camera is the LAST cell of the same scrolling row — a photo is just
    /// another way to log this round, not a second, competing control — and one
    /// footnote sits under the row. Everything is disabled while a photo uploads.
    private var heroRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Camera pinned OUTSIDE the scrolling row so it is always in the first
            // viewport; the glasses scroll beside it and the next one peeks.
            HStack(alignment: .bottom, spacing: 8) {
                DrinkPickerView(
                    selected: $selectedDrink,
                    isBusy: viewModel.isUploadingPhoto,
                    onPick: { kind in
                        // The row springs in from the feed animation, as before.
                        Task { await viewModel.logBeer(photoJPEG: nil, drink: kind) }
                    }
                )
                cameraCell
                    .padding(.bottom, 4)
                    .layoutPriority(1)   // the row scrolls; the camera keeps its width
            }

            Text("Tap a glass to log it")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(viewModel.isUploadingPhoto)
    }

    /// The camera as a glass-row cell: a 56 pt round button with its own caption,
    /// so it lines up with the glasses' labels along the bottom of the row.
    private var cameraCell: some View {
        VStack(spacing: 4) {
            Button {
                Haptics.light()
                showCamera = true
            } label: {
                Image(systemName: "camera.fill")
            }
            .buttonStyle(RoundIconButtonStyle(size: 56))
            .accessibilityLabel("Log a drink with a photo")
            .accessibilityHint("Uses the last glass you picked")
            .accessibilityIdentifier("home.camera")

            Text("Photo")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("Nobody to hear you yet")
                .font(Theme.displayTitle2)
            Text("Add a mate and they get a push the moment you tap.")
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

    private func feedRow(_ beer: BeerLog, now: Date) -> some View {
        let isMine = beer.ownerUid == profile.id
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        // At accessibility sizes the chip and the cheers control drop under the
        // name instead of squeezing it into an ellipsis.
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))

        return HStack(alignment: isAccessibilitySize ? .top : .center, spacing: 12) {
            drinkGlass(for: beer, name: isMine ? profile.displayName : beer.ownerName, now: now)

            layout {
                VStack(alignment: .leading, spacing: 2) {
                    // "You" stays a standalone static text — the UI test looks for it.
                    Text(isMine ? "You" : beer.ownerName)
                        .font(.headline)
                        .lineLimit(isAccessibilitySize ? nil : 1)
                    metadataLine(for: beer, isAccessibilitySize: isAccessibilitySize)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    photoChip(for: beer, now: now)
                    replyPills(for: beer)
                    reactionControl(for: beer, isMine: isMine)
                }
            }
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
                // Quick replies first: the everyday actions, above the reporting
                // ones (long-press is the only place they live on a row — the row
                // itself stays a two-control affair).
                replyButton(for: beer, kind: .onMyWay)
                replyButton(for: beer, kind: .jealous)
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

    /// Relative time, with the opt-in place after it when the beer carries one:
    /// "2 min · 📍 Café De Zon". One secondary line; the place is the part that
    /// truncates, since the time is what every row promises.
    @ViewBuilder
    private func metadataLine(for beer: BeerLog, isAccessibilitySize: Bool) -> some View {
        let time = Text(beer.createdAt, style: .relative)
        let place: String? = beer.place.flatMap { $0.isEmpty ? nil : $0 }
        Group {
            if let place {
                (time + Text(" · 📍 \(place)"))
                    .truncationMode(.tail)
                    // Concatenated Text is a single accessibility element, so the
                    // label has to carry both halves — the pin glyph would
                    // otherwise be read out as "pin".
                    .accessibilityLabel(
                        "\(beer.createdAt.formatted(.relative(presentation: .named))), at \(place)"
                    )
            } else {
                time
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(isAccessibilitySize ? nil : 1)
    }

    /// The glass that stands in for an avatar: what they are drinking, draining
    /// from full at the tap to empty when the beer expires 24 hours later.
    private func drinkGlass(for beer: BeerLog, name: String, now: Date) -> some View {
        let level = beer.fillLevel(now: now)
        return DrinkGlassView(kind: beer.drink, level: level, size: 44)
            .frame(width: 56, height: 56)
            .background(Theme.accentSoft, in: Circle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(name) is having \(beer.drink.label), glass \(Int(level * 100)) percent"
            )
    }

    @ViewBuilder
    private func photoChip(for beer: BeerLog, now: Date) -> some View {
        switch beer.photoChipState(viewedByMe: viewModel.viewedBeerIds.contains(beer.id), now: now) {
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

    /// One quick reply per mate per beer, from the row's long-press menu. Already
    /// replied (this launch or an earlier one — the server mirrors replies onto
    /// the beer) disables both items rather than hiding them.
    private func replyButton(for beer: BeerLog, kind: ReplyKind) -> some View {
        Button {
            Haptics.light()
            Task { await viewModel.reply(beer, kind: kind, myUid: profile.id) }
        } label: {
            Text("\(kind.label) \(kind.emoji)")
        }
        .disabled(beer.replies[profile.id] != nil)
        .accessibilityIdentifier("home.reply.\(kind.rawValue)")
    }

    /// Who's on the way and who's sulking. Shown on every row, your own included:
    /// the owner is exactly who wants to know a mate is heading over.
    @ViewBuilder
    private func replyPills(for beer: BeerLog) -> some View {
        ForEach(ReplyKind.allCases, id: \.self) { kind in
            let count = beer.replyCount(kind)
            if count > 0 {
                StatusPill(text: "\(kind.emoji) \(count)")
                    .accessibilityLabel(Self.replyLabel(kind, count: count))
            }
        }
    }

    /// VoiceOver reads the tally, not the emoji ("2 on their way", "1 jealous").
    private static func replyLabel(_ kind: ReplyKind, count: Int) -> String {
        switch kind {
        case .onMyWay: return "\(count) on their way"
        case .jealous: return "\(count) jealous"
        }
    }

    /// Your own row carries no cheers button — you can't cheers yourself, and a
    /// permanently disabled control is noise. It shows the tally only once there
    /// is one to show.
    @ViewBuilder
    private func reactionControl(for beer: BeerLog, isMine: Bool) -> some View {
        if isMine {
            if beer.cheersCount > 0 {
                StatusPill(text: "🍻 \(beer.cheersCount)")
                    .accessibilityLabel("\(beer.cheersCount) cheers")
            }
        } else {
            cheersButton(for: beer)
        }
    }

    private func cheersButton(for beer: BeerLog) -> some View {
        let isDisabled = viewModel.cheersedBeerIds.contains(beer.id)
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
