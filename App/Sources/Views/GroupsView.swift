import BeerKit
import SwiftUI
import UIKit

// COMPILE-PARKED (Task 12): no Xcode on this machine — written against
// iOS 17 SDK APIs + BeerKit's GroupServicing, not yet compiled.

/// Groups: the battle screen. Tim: "je kan groepen maken waarbij je de counter
/// kan bijhouden hoeveel bier er wordt gelogd, zodat je ook kan battelen tegen
/// andere groepen; er is een leaderboard-pagina waar je kan zien welke groepen
/// er zijn en hoeveel er deze dag al gelogd is."
///
/// Two sections: my groups and the whole leaderboard for today, with the two
/// actions that change membership in a clear row of their own between them. My
/// groups are marked by an amber name, not by a washed row. Consumes only
/// `GroupServicing` + `LeaderboardViewModel` — never Firebase types.
///
/// Design: docs/design/direction.md / DESIGN.md — inset grouped sections,
/// eyebrow headers, one amber accent on the pills and the rank disc, system
/// everything else. With nothing to rank yet, one Home-style empty state
/// claims half the viewport and the two sections stay away.
struct GroupsView: View {
    @StateObject private var viewModel: LeaderboardViewModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Only used for the invite copy ("@tim wants you in …"); the leaderboard
    /// itself is entirely server-ranked.
    private let profile: UserProfile
    private let groupService: any GroupServicing

    /// Bumped to restart the leaderboard stream (pull-to-refresh), the same way
    /// HomeView restarts its feed with `feedEpoch`.
    @State private var epoch = 0
    /// The server counts in Europe/Amsterdam; re-read on every (re)start so a
    /// day rollover while the app is open doesn't leave yesterday on screen.
    @State private var today = GroupDay.today()
    @State private var showCreateSheet = false
    @State private var showJoinSheet = false
    @State private var detailGroup: GroupSummary?
    @State private var infoMessage: String?

    init(profile: UserProfile, groupService: any GroupServicing) {
        self.profile = profile
        self.groupService = groupService
        _viewModel = StateObject(wrappedValue: LeaderboardViewModel(service: groupService))
    }

    var body: some View {
        NavigationStack {
            // The reader only measures the viewport, so the empty state can
            // claim half of it — the same move as Home's.
            GeometryReader { proxy in
                List {
                    if viewModel.groups.isEmpty {
                        // Nothing to rank yet: one empty state carrying the two
                        // pills that fix it, and no sections behind it.
                        Section {
                            emptyState
                                .frame(minHeight: max(0, proxy.size.height * 0.5))
                                .listRowInsets(EdgeInsets(top: 24, leading: 24, bottom: 24, trailing: 24))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                        }
                    } else {
                        myGroupsSection
                        actionSection
                        leaderboardSection
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable { epoch += 1 }
                // Changing the id cancels the previous start(); the new one awaits
                // the old stream's teardown itself, so no sleep is needed here.
                .task(id: epoch) {
                    today = GroupDay.today()
                    await viewModel.start()
                }
                // A `/join/<code>` link lands in AppState and waits for this screen.
                .onAppear { consumePendingGroupCode() }
                .onChange(of: appState.pendingGroupCode) { _, _ in consumePendingGroupCode() }
            }
            .navigationTitle("Groups")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCreateSheet) {
                CreateGroupSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinGroupSheet(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $detailGroup) { group in
                GroupDetailSheet(
                    group: group,
                    today: today,
                    viewModel: viewModel,
                    groupService: groupService,
                    inviterUsername: profile.username
                )
                .presentationDetents([.large])
            }
            // While a sheet is up it owns the alerts (it presents the same
            // `errorMessage`), so this one stays out of the way.
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        // Only the join flow raises this one, so the title is its headline.
        .alert("You're in!", isPresented: infoBinding) {
            Button("Cheers", role: .cancel) {}
        } message: {
            Text(infoMessage ?? "")
        }
    }

    // MARK: - Empty state

    /// The Home pattern: a rounded title, one secondary line, then the actions.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No groups yet")
                .font(Theme.displayTitle2)
            Text("Make one, share the code, and every drink your crew logs counts today.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            actionRow(centred: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - My groups

    private var myGroupsSection: some View {
        Section {
            if viewModel.mine.isEmpty {
                Text("Not in a group yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(viewModel.mine) { group in
                    groupRow(group)
                        .accessibilityHint("Opens the group, with its join code")
                        .accessibilityIdentifier("groups.mine.\(group.id)")
                }
            }
        } header: {
            Eyebrow(text: "My groups")
        }
    }

    /// The two actions that change membership, in a clear row of their own: kept
    /// out of the section above so that card keeps its bottom corners.
    private var actionSection: some View {
        Section {
            actionRow(centred: false)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listSectionSpacing(8)
    }

    /// Create and join. `centred` is the empty state, where they sit under the
    /// copy rather than on the leading edge of a row.
    private func actionRow(centred: Bool) -> some View {
        // At accessibility sizes two pills won't fit side by side.
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: centred ? .center : .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            Button {
                Haptics.light()
                showCreateSheet = true
            } label: {
                Text("Create a group")
            }
            .buttonStyle(PillButtonStyle(emphasis: .filled))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Create a group")
            .accessibilityIdentifier("groups.create")

            Button {
                Haptics.light()
                showJoinSheet = true
            } label: {
                Text("Join with code")
            }
            .buttonStyle(PillButtonStyle(emphasis: .tinted))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityLabel("Join a group with a code")
            .accessibilityIdentifier("groups.join")

            // Left-aligned in a row; centred in the empty state, where the
            // stack does the centring itself.
            if !dynamicTypeSize.isAccessibilitySize, !centred {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        Section {
            ForEach(viewModel.ranked) { group in
                groupRow(group)
                    .accessibilityHint("Opens the group")
                    .accessibilityIdentifier("groups.row.\(group.id)")
            }
        } header: {
            Eyebrow(text: "Leaderboard · \(todayLabel)")
        }
    }

    /// One anatomy for both sections: the rank disc, the name over its tally,
    /// and today's count on the trailing edge. A group of mine is marked by the
    /// amber name — the row itself stays a plain card. At accessibility sizes
    /// the pill drops under the text.
    private func groupRow(_ group: GroupSummary) -> some View {
        let rank = viewModel.rank(of: group)
        let count = group.countToday(today)
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return Button {
            Haptics.light()
            detailGroup = group
        } label: {
            HStack(alignment: isAccessibilitySize ? .top : .center, spacing: 12) {
                rankBadge(rank)
                layout {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.name)
                            .font(.headline)
                            .foregroundStyle(group.isMine ? Theme.accentInk : .primary)
                            .lineLimit(2)
                        Text(subtitle(for: group))
                            .font(.subheadline)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    StatusPill(text: "🍺 \(count)")
                        // The count ticks while the screen is open.
                        .contentTransition(.numericText())
                }
            }
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            // The system aligns a separator to the row's first Text, so the
            // crown row (an Image) got a name-aligned line and the `#n` rows a
            // badge-aligned one. Pin every separator to the name.
            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + 30 + 12 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rankSpoken(rank)), \(group.name), \(count) today, \(group.totalCount) total, \(mates(group.memberCount))\(group.isMine ? ", one of your groups" : "")")
    }

    /// The one rank marker, drawn: a crown for the leader, `#n` for everyone
    /// else — amber on the wash for the podium, quiet grey below it.
    private func rankBadge(_ rank: Int) -> some View {
        let isPodium = rank <= 3
        return Group {
            if rank == 1 {
                Image(systemName: "crown.fill")
                    .font(.caption.weight(.bold))
            } else {
                Text("#\(rank)")
                    .font(.caption.weight(.bold).monospacedDigit())
            }
        }
        .foregroundStyle(isPodium ? Theme.accentInk : Color.secondary)
        .frame(width: 30, height: 30)
        .background(isPodium ? Theme.accentSoft : Color(.tertiarySystemFill), in: Circle())
        .accessibilityHidden(true)
    }

    private func rankSpoken(_ rank: Int) -> String {
        switch rank {
        case 1: return "First place"
        case 2: return "Second place"
        case 3: return "Third place"
        default: return "Number \(rank)"
        }
    }

    private func subtitle(for group: GroupSummary) -> String {
        "\(mates(group.memberCount)) · \(group.totalCount) total"
    }

    private func mates(_ count: Int) -> String {
        count == 1 ? "1 mate" : "\(count) mates"
    }

    /// "Thu 10 Sep" for the day the server counts in — parsed and printed in
    /// Amsterdam, so a user abroad still reads the day their beers land on.
    private var todayLabel: String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: today) else { return "today" }
        let display = DateFormatter()
        display.calendar = Calendar(identifier: .gregorian)
        display.timeZone = TimeZone(identifier: "Europe/Amsterdam")
        display.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return display.string(from: date)
    }

    // MARK: - Actions

    /// `https://beerwithme-prod.web.app/join/<code>`: AppState holds the code
    /// until this screen exists (cold launch, or a launch into onboarding).
    private func consumePendingGroupCode() {
        guard let code = appState.pendingGroupCode else { return }
        appState.pendingGroupCode = nil
        showCreateSheet = false
        showJoinSheet = false
        Task {
            if await viewModel.join(code: code) {
                Haptics.success()
                infoMessage = "Your drinks count for this group from now on."
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !showCreateSheet && !showJoinSheet },
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

// MARK: - Detail

/// One group: its counters, its mates, and — for a group I'm in — the join code
/// with the link that gets a mate straight in, plus the way out.
private struct GroupDetailSheet: View {
    let group: GroupSummary
    let today: String
    @ObservedObject var viewModel: LeaderboardViewModel
    let groupService: any GroupServicing
    let inviterUsername: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var members: [GroupMember] = []
    @State private var isLoadingMembers = true
    @State private var membersFailed = false
    @State private var showLeaveDialog = false
    /// True for 1.5 s after a tap on the code: the "Copied" pill is the receipt.
    @State private var didCopy = false
    /// Latest tap wins — an older one must not retire a newer pill.
    @State private var copyToken = 0

    /// The counters keep ticking while the sheet is open: read the live row from
    /// the leaderboard, falling back to the snapshot the row was tapped with
    /// (which is also what's left after leaving).
    private var live: GroupSummary {
        viewModel.groups.first { $0.id == group.id } ?? group
    }

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if let code = live.code { inviteSection(code: code) }
                membersSection
                if live.isMine { leaveSection }
            }
            .listStyle(.insetGrouped)
            // The name is the title, so the header carries only the counters.
            .navigationTitle(live.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("groups.detail.done")
                }
            }
            .task { await loadMembers() }
        }
    }

    private var headerSection: some View {
        Section {
            statPills
                .padding(.vertical, 6)
        }
    }

    private var statPills: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
        let count = live.countToday(today)
        return layout {
            StatusPill(text: "🍺 \(count) today")
            StatusPill(text: "\(live.totalCount) total")
            StatusPill(text: live.memberCount == 1 ? "1 mate" : "\(live.memberCount) mates")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) today, \(live.totalCount) in total, \(live.memberCount) mates")
    }

    /// Only for a group I'm in: the code is what a mate types, the link is what
    /// they tap. Both carry the same six characters.
    private func inviteSection(code: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                // Tapping the code copies it: the pill is the receipt, and it
                // retires itself a beat later.
                Button {
                    UIPasteboard.general.string = code
                    Haptics.light()
                    flashCopied()
                } label: {
                    HStack(spacing: 12) {
                        Text(code)
                            .font(.system(.title, design: .rounded, weight: .bold))
                            .tracking(4)
                        Spacer(minLength: 8)
                        if didCopy {
                            StatusPill(text: "Copied")
                        }
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(Theme.quick, value: didCopy)
                .accessibilityLabel("Join code, \(code.map { String($0) }.joined(separator: " "))")
                .accessibilityHint("Copies the code")
                .accessibilityIdentifier("groups.detail.code")
                Text("Read the code out, or send the link — it opens the app and drops them in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ShareLink(
                    item: URL(string: MateLink.joinLink(for: code))!,
                    subject: Text("Join my PubDates group"),
                    message: Text("@\(inviterUsername) wants you in \(live.name) on PubDates 🍺 Tap the link, or use code \(code).")
                ) {
                    Label("Invite to group", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(PillButtonStyle(emphasis: .tinted))
                .accessibilityLabel("Invite a mate to this group")
                .accessibilityIdentifier("groups.detail.invite")
            }
            .padding(.vertical, 4)
        } header: {
            Eyebrow(text: "Join code")
        }
    }

    private var membersSection: some View {
        Section {
            if isLoadingMembers {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Counting heads…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            } else if membersFailed {
                Text("Couldn't load the mates in this group.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if members.isEmpty {
                Text("Nobody in here yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                // Same anatomy as a mate row in Friends: avatar, name over
                // @username.
                ForEach(members) { member in
                    HStack(spacing: 12) {
                        AvatarView(name: member.displayName, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(.headline)
                            Text("@\(member.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(member.displayName), @\(member.username)")
                }
            }
        } header: {
            Eyebrow(text: "Mates")
        }
    }

    private var leaveSection: some View {
        Section {
            Button(role: .destructive) {
                showLeaveDialog = true
            } label: {
                Text("Leave group")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("Leave \(live.name)")
            .accessibilityIdentifier("groups.detail.leave")
            .confirmationDialog(
                "Leave \(live.name)?",
                isPresented: $showLeaveDialog,
                titleVisibility: .visible
            ) {
                Button("Leave group", role: .destructive) {
                    let target = live
                    dismiss()
                    Task { await viewModel.leave(target) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your beers stop counting for this group. You can join again with the code.")
            }
        }
    }

    /// Shows "Copied" for 1.5 s, then lets it go.
    private func flashCopied() {
        copyToken += 1
        let token = copyToken
        didCopy = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if copyToken == token { didCopy = false }
        }
    }

    private func loadMembers() async {
        do {
            members = try await groupService.members(of: group.id)
        } catch {
            membersFailed = true
        }
        isLoadingMembers = false
    }
}

// MARK: - Create

private struct CreateGroupSheet: View {
    @ObservedObject var viewModel: LeaderboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isWorking = false

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Name it after the crew. Every beer a mate logs counts for the group.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("Group name", text: $name)
                        .font(.body)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit { if canCreate { create() } }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(
                            Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        )
                        .accessibilityLabel("Group name")
                        .accessibilityIdentifier("groups.name")
                        // The service rejects a longer name anyway; stop it here.
                        .onChange(of: name) { _, newValue in
                            if newValue.count > GroupSummary.nameMaxLength {
                                name = String(newValue.prefix(GroupSummary.nameMaxLength))
                            }
                        }

                    // The counter only earns its place near the ceiling.
                    if name.count >= 20 {
                        Text("\(name.count)/\(GroupSummary.nameMaxLength)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }

                    Button {
                        Haptics.light()
                        create()
                    } label: {
                        if isWorking {
                            ProgressView()
                                .tint(Theme.onAccent)
                        } else {
                            Text("Create")
                        }
                    }
                    .buttonStyle(HeroButtonStyle())
                    .accessibilityIdentifier("groups.createConfirm")
                    .accessibilityLabel("Create the group")
                    // The style can't read `isEnabled`, so the disabled look is
                    // set here (same as onboarding's Claim button).
                    .disabled(!canCreate)
                    .opacity(canCreate ? 1 : 0.5)
                    .animation(Theme.quick, value: canCreate)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("groups.createCancel")
                }
            }
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var canCreate: Bool { !isWorking && !trimmedName.isEmpty }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func create() {
        guard canCreate else { return }
        isWorking = true
        Task {
            let created = await viewModel.create(name: trimmedName)
            isWorking = false
            if created {
                Haptics.success()
                dismiss()
            }
        }
    }
}

// MARK: - Join

private struct JoinGroupSheet: View {
    @ObservedObject var viewModel: LeaderboardViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isWorking = false

    private var trimmedCode: String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Ask a mate for the group's six characters — or just tap their invite link.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("6-character code", text: $code)
                        .font(.system(.title3, design: .rounded, weight: .bold))
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { if canJoin { join() } }
                        .padding(.horizontal, 14)
                        .frame(minHeight: 52)
                        .background(
                            Theme.surface,
                            in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        )
                        .accessibilityLabel("Group join code")
                        .accessibilityIdentifier("groups.code")
                        .onChange(of: code) { _, newValue in
                            let cleaned = newValue.uppercased().filter { $0.isLetter || $0.isNumber }
                            let capped = String(cleaned.prefix(6))
                            if capped != newValue { code = capped }
                        }

                    Button {
                        Haptics.light()
                        join()
                    } label: {
                        if isWorking {
                            ProgressView()
                                .tint(Theme.onAccent)
                        } else {
                            Text("Join")
                        }
                    }
                    .buttonStyle(HeroButtonStyle())
                    .accessibilityIdentifier("groups.joinConfirm")
                    .accessibilityLabel("Join the group")
                    .disabled(!canJoin)
                    .opacity(canJoin ? 1 : 0.5)
                    .animation(Theme.quick, value: canJoin)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Join a group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("groups.joinCancel")
                }
            }
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var canJoin: Bool { !isWorking && trimmedCode.count == 6 }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func join() {
        guard canJoin else { return }
        isWorking = true
        Task {
            let joined = await viewModel.join(code: trimmedCode)
            isWorking = false
            if joined {
                Haptics.success()
                dismiss()
            }
        }
    }
}
