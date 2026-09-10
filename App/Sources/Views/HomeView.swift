import BeerKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// The main screen: the drink picker — a tap pours the glass and goes straight
/// to the camera — and the live feed.
/// Consumes ONLY BeerKit (`HomeViewModel`, protocols) — never Firebase types;
/// the screenshot reporter closure is injected pre-wired by RootView.
///
/// Layout follows docs/design/direction.md: large title "PubDates" collapsing on
/// scroll, then the hero — a row of drawn glasses, one tap each (all inside the
/// scroll view, so the title collapses natively), then the last 24 hours of
/// drinks as plain rows.
/// Every row carries the glass that was picked, draining as the 24 hours run out.
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let profile: UserProfile
    private let friendService: any FriendServicing
    private let screenshotReporter: @Sendable (String) async -> Void

    /// True while the camera owns the screen. It is opened by a glass tap, never
    /// on its own: a drink without a photo is not a drink (Tim: "ik wil eigenlijk
    /// dat je altijd een foto moet toevoegen").
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
    /// The glass tapped this session (marks the favourite tile in the picker).
    @State private var selectedDrink: DrinkKind?
    /// The glass that has been poured and is waiting for its photo. Set on the
    /// tap, consumed by `onCapture` — so a drink still sitting here when the
    /// camera closes is a cancelled shot, and nothing gets logged.
    @State private var pendingDrink: DrinkKind?
    /// Bumped when the flow a tap started is over (photo taken, or cancelled):
    /// the picker drops its local pour and the feed owns the glass again.
    @State private var pourReset = 0
    /// Anchor for the feed's minute tick. Stable across re-renders, unlike a
    /// fresh `.now` in the body, so the schedule never restarts.
    @State private var glassClock = Date()
    /// True for 1.5 s after a locked tap: the footnote goes amber so the reason
    /// the tap did nothing is where the eye already is.
    @State private var lockedNudge = false
    /// Latest nudge wins — an older one must not switch the caption back early.
    @State private var lockedNudgeToken = 0

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
                // chip) without a timer of our own. While the one-minute lock
                // runs, the same tick goes to 1 s so "next in Ns" counts down —
                // and drops back to 60 s the moment it is over.
                TimelineView(.periodic(from: glassClock, by: isLocked ? 1 : 60)) { context in
                    List {
                        Section {
                            heroRow(now: context.date)
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
        // The second half of a glass tap: the shot is what logs the drink. The
        // camera dismisses itself on both "Use photo" and Cancel, so `onDismiss`
        // is where a cancelled round is undone.
        .fullScreenCover(isPresented: $showCamera, onDismiss: cameraDismissed) {
            CameraView { data in
                // Consuming `pendingDrink` here is also how `cameraDismissed()`
                // tells a used camera from a cancelled one.
                let drink = pendingDrink ?? .pils
                pendingDrink = nil
                pourReset += 1 // the logged row takes the glass from here
                Task { await viewModel.logBeer(photoJPEG: data, drink: drink, myUid: profile.id) }
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

    /// The glasses own the screen: pick what you are drinking (Tim: "je moet
    /// selecteren wat voor drankje") and the tap pours that glass, then hands the
    /// screen to the camera — every drink carries a photo (Tim: "pour the glass en
    /// dan gaat hij gelijk naar camera modus"), so the tap itself logs nothing.
    /// The glass you picked STAYS full and drains with the drink, and for the
    /// minute after a log every glass is locked: a tap shakes instead of pouring
    /// ("the pour animation should not then clear, but it should also prevent
    /// someone from spamming the button"). One footnote sits under the row, and
    /// everything is disabled while a photo uploads.
    private func heroRow(now: Date) -> some View {
        // Your own newest drink: which glass stays full, and how full it still is.
        let mine = viewModel.latestOwnDrink(myUid: profile.id)
        return VStack(alignment: .leading, spacing: 8) {
            DrinkPickerView(
                selected: $selectedDrink,
                isBusy: viewModel.isUploadingPhoto,
                currentDrink: mine?.drink,
                // Draining on the timeline tick, so the glass in the picker
                // and the glass on your feed row are the same drink.
                currentLevel: mine?.fillLevel(now: now) ?? 0,
                isLocked: isLocked,
                pourReset: pourReset,
                onPick: { kind in
                    // Remembered, not logged: the camera takes it from here.
                    pendingDrink = kind
                    openCameraAfterPour(kind)
                },
                onLockedTap: { flashLockedCaption() }
            )

            // One footnote does both jobs: the invitation, and — while the lock
            // runs — the reason and the wait, counting down on the same tick.
            Text(caption)
                .font(.footnote)
                .foregroundStyle(lockedNudge ? Theme.accentInk : Color.secondary)
                .animation(Theme.quick, value: lockedNudge)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(viewModel.isUploadingPhoto)
    }

    // MARK: - Pour, then camera

    /// The pour gets the screen to itself before the camera takes it: the glass
    /// fills over `Theme.pour` (350 ms, or the 180 ms `Theme.quick` under Reduce
    /// Motion) and the cover comes up on the beat after it, so the gesture reads
    /// as one move — pour, then shoot — rather than a sheet cutting it off.
    private func openCameraAfterPour(_ kind: DrinkKind) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(reduceMotion ? 0.18 : 0.35))
            // A second glass tapped during the pour wins; only the drink still
            // pending gets a camera.
            guard pendingDrink == kind, !showCamera else { return }
            showCamera = true
        }
    }

    /// The camera closed. `onCapture` consumes `pendingDrink`, so one still
    /// sitting here means the shot was cancelled: the glass goes back to its
    /// resting level and nothing is logged — except under the UI-test flag below.
    private func cameraDismissed() {
        guard let drink = pendingDrink else { return }
        pendingDrink = nil
        pourReset += 1
        if Self.logsCancelledDrinkWithoutPhoto {
            Task { await viewModel.logBeer(photoJPEG: nil, drink: drink, myUid: profile.id) }
        }
    }

    /// The CI simulator has no camera, so the screenshot test can never take a
    /// photo: launched with `-UITestLogWithoutPhoto`, a cancelled camera logs the
    /// pending drink without one. DEBUG-only and opt-in — always false in a
    /// shipped build, where a cancelled shot logs nothing.
    private static var logsCancelledDrinkWithoutPhoto: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-UITestLogWithoutPhoto")
        #else
        false
        #endif
    }

    // MARK: - The one-minute lock

    /// True while `HomeViewModel` would refuse the next drink (60 s).
    private var isLocked: Bool {
        viewModel.cooldownRemaining(myUid: profile.id) > 0
    }

    /// The footnote under the row: the invitation, or the wait.
    private var caption: String {
        let remaining = viewModel.cooldownRemaining(myUid: profile.id)
        guard remaining > 0 else { return "Tap a glass, snap your drink" }
        // Ceil, so the last second still reads "next in 1s" rather than "0s".
        return "Enjoy that one first · next in \(Int(remaining.rounded(.up)))s"
    }

    /// A locked tap flashes the footnote amber for a beat, then lets it go quiet
    /// again — the countdown itself stays put.
    private func flashLockedCaption() {
        lockedNudgeToken += 1
        let token = lockedNudgeToken
        lockedNudge = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if lockedNudgeToken == token { lockedNudge = false }
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
