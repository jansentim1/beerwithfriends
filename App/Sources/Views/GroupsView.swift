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

    /// Me: the invite copy ("@tim wants you in …") and, in the detail sheet, which
    /// row is mine and whose notes carry a delete. The leaderboard itself is
    /// entirely server-ranked.
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
                .scrollContentBackground(.hidden)
                .background(Theme.ground.ignoresSafeArea())
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
                    profile: profile
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
        .listRowBackground(Theme.surface)
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
        .listRowBackground(Theme.surface)
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
                RankBadge(rank: rank)
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
            .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + RankBadge.size + 12 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(rankSpoken(rank)), \(group.name), \(count) today, \(group.totalCount) total, \(mates(group.memberCount))\(group.isMine ? ", one of your groups" : "")")
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
            get: { viewModel.errorMessage != nil && !showCreateSheet && !showJoinSheet && detailGroup == nil },
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

// MARK: - Rank marker

/// The one rank marker, drawn: a crown for the leader, `#n` for everyone else —
/// amber on the wash for the podium, quiet grey below it. Shared by the group
/// leaderboard and the ranking of people inside a group, because they are the
/// same idea at two scales.
private struct RankBadge: View {
    let rank: Int
    static let size: CGFloat = 30

    var body: some View {
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
        .frame(width: Self.size, height: Self.size)
        .background(isPodium ? Theme.accentSoft : Color(.tertiarySystemFill), in: Circle())
        .accessibilityHidden(true)
    }
}

private func rankSpoken(_ rank: Int) -> String {
    switch rank {
    case 1: return "First place"
    case 2: return "Second place"
    case 3: return "Third place"
    default: return "Number \(rank)"
    }
}

// MARK: - Detail

/// One group: its counters, its people ranked against each other, the notes they
/// leave for the group, and — for a group I'm in — the join code with the link
/// that gets a mate straight in, the one-tap way to make the group mates, plus
/// the way out.
private struct GroupDetailSheet: View {
    let group: GroupSummary
    let today: String
    @ObservedObject var viewModel: LeaderboardViewModel
    let groupService: any GroupServicing
    /// Me: the invite copy, the amber name on my own row, whose notes carry a
    /// delete, and who the bulk mate request skips.
    let profile: UserProfile

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var members: [GroupMember] = []
    @State private var isLoadingMembers = true
    @State private var membersFailed = false
    @State private var notes: [GroupNote] = []
    @State private var isLoadingNotes = true
    @State private var notesFailed = false
    @State private var noteText = ""
    @State private var isSendingNote = false
    /// One quiet line under the composer — a failed send or a note the server's
    /// cooldown swallowed. Never an alert: nothing here is broken.
    @State private var noteStatus: String?
    /// Who I'm already mates with, nil until `friends()` has answered (and left
    /// nil when it fails, so nothing is assumed about who to ask).
    @State private var mateIds: Set<String>?
    @State private var isAddingMates = false
    /// The one summary a bulk mate request reports, instead of eight alerts.
    @State private var mateSummary: String?
    @State private var showLeaveDialog = false
    /// True for 1.5 s after a tap on the code: the "Copied" pill is the receipt.
    @State private var didCopy = false
    /// Latest tap wins — an older one must not retire a newer pill.
    @State private var copyToken = 0
    /// A join is in flight: `joinGroup` is not idempotent, so a second tap would
    /// come back ALREADY_MEMBER.
    @State private var isJoining = false

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
                // The code is readable for every group; only a member gets to see it.
                if live.isMine, let code = live.code { inviteSection(code: code) }
                membersSection
                // Notes are members-only both ways by rule, so a group I'm not in
                // gets neither the list nor the composer.
                if live.isMine { notesSection }
                if canAskMates { matesSection }
                if live.isMine { leaveSection } else { joinSection }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.ground.ignoresSafeArea())
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
            .task {
                await loadMembers()
                if live.isMine {
                    await loadNotes()
                    await loadMateIds()
                }
            }
            // This sheet sits on top of GroupsView, whose alert stays quiet while
            // a sheet is up — so a failed join has to land here or nowhere.
            .alert("Oops", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
        // One receipt for the whole batch, so it can't stack with the join alert
        // above: that one lives on the List, this one on the stack.
        .alert("Mates", isPresented: mateSummaryBinding) {
            Button("Cheers", role: .cancel) {}
        } message: {
            Text(mateSummary ?? "")
        }
    }

    private var headerSection: some View {
        Section {
            statPills
                .padding(.vertical, 6)
        }
        .listRowBackground(Theme.surface)
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
                    message: Text("@\(profile.username) wants you in \(live.name) on PubDates 🍺 Tap the link, or use code \(code).")
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
        .listRowBackground(Theme.surface)
    }

    /// The people in this group, ranked against each other on the same rule as
    /// the group leaderboard (today, then total, then name).
    private var ranking: GroupMemberRanking { GroupMemberRanking(members, today: today) }

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
                ForEach(ranking.members) { member in
                    memberRow(member)
                }
            }
        } header: {
            Eyebrow(text: "Ranking")
        } footer: {
            // A quiet day is a state, not a bug: everyone still has a place, and
            // the line says what would change it.
            if !isLoadingMembers, !members.isEmpty, (ranking.leader?.countToday(today) ?? 0) == 0 {
                Text("Nobody's logged a thing today. First one takes the crown.")
            }
        }
        .listRowBackground(Theme.surface)
    }

    /// The group row's anatomy, one scale down: the rank marker takes the leading
    /// slot (an avatar beside it made two discs fight over the same row), the
    /// name goes amber when it's me, today's count is the headline number in the
    /// pill and the total is the quiet one under the name.
    private func memberRow(_ member: GroupMember) -> some View {
        let rank = ranking.rank(of: member.id)
        let count = member.countToday(today)
        let isMe = member.id == profile.id
        let isAccessibilitySize = dynamicTypeSize.isAccessibilitySize
        let layout = isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return HStack(alignment: isAccessibilitySize ? .top : .center, spacing: 12) {
            RankBadge(rank: rank)
            layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                        .font(.headline)
                        .foregroundStyle(isMe ? Theme.accentInk : .primary)
                        .lineLimit(isAccessibilitySize ? nil : 1)
                    Text("@\(member.username) · \(member.totalCount) total")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(isAccessibilitySize ? nil : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StatusPill(text: "🍺 \(count)")
                    .contentTransition(.numericText())
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        // Same reason as the group rows: pin the separator to the name, not to
        // whatever the badge happens to draw.
        .alignmentGuide(.listRowSeparatorLeading) { d in d[.leading] + RankBadge.size + 12 }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(rankSpoken(rank)), \(member.displayName)\(isMe ? ", you" : ""), @\(member.username), \(count) today, \(member.totalCount) total")
        .accessibilityIdentifier("groups.detail.member.\(member.id)")
    }

    // MARK: - Notes

    /// A line to the group — "wilde even meedelen dat er lekker wordt gejand op
    /// deze zaterdagmiddag". The composer sits at the top of the section, the way
    /// the Mates search does, and everybody's notes follow newest first.
    private var notesSection: some View {
        Section {
            composerRow
            if isLoadingNotes {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading the group…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
            } else if notesFailed {
                Text("Couldn't load the notes.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else if notes.isEmpty {
                Text("Nothing said yet. Tell them where you are.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(notes) { note in
                    noteRow(note)
                }
            }
        } header: {
            Eyebrow(text: "Notes")
        } footer: {
            // The server drops a second note inside 60 s, so say it before it
            // happens rather than explaining a vanished line afterwards.
            Text("Everyone in the group gets a push. One note a minute.")
        }
        .listRowBackground(Theme.surface)
    }

    private var composerRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                noteField
                sendNoteButton
            }
            if noteText.count >= GroupNote.textMaxLength - 20 {
                Text("\(noteText.count)/\(GroupNote.textMaxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if let noteStatus {
                Text(noteStatus)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
        .animation(Theme.quick, value: noteStatus)
    }

    /// A bare field in the grouped cell, like the Mates search — no nested box.
    private var noteField: some View {
        TextField("Say something to the group", text: $noteText)
            .submitLabel(.send)
            .onSubmit { sendNote() }
            .frame(minHeight: 44)
            .accessibilityLabel("Note to the group")
            .accessibilityIdentifier("groups.detail.noteField")
            // The rules refuse a longer note anyway; stop it here.
            .onChange(of: noteText) { _, newValue in
                if newValue.count > GroupNote.textMaxLength {
                    noteText = String(newValue.prefix(GroupNote.textMaxLength))
                }
            }
    }

    private var sendNoteButton: some View {
        // The pill style can't read `isEnabled`, so the disabled look is chosen
        // here: quiet, never amber at half strength (same as the Mates Add pill).
        Button {
            sendNote()
        } label: {
            Text("Send")
                .opacity(isSendingNote ? 0 : 1)
                .overlay {
                    if isSendingNote {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Color.secondary)
                    }
                }
                .frame(minHeight: 44)
        }
        .buttonStyle(PillButtonStyle(emphasis: canSendNote ? .filled : .quiet))
        .disabled(!canSendNote)
        .animation(Theme.quick, value: canSendNote)
        .accessibilityLabel("Send the note")
        .accessibilityIdentifier("groups.detail.noteSend")
    }

    private var canSendNote: Bool { !isSendingNote && GroupNote.sanitize(noteText) != nil }

    private func noteRow(_ note: GroupNote) -> some View {
        let isMine = note.isMine(profile.id)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(note.displayName)
                    .font(.headline)
                    .foregroundStyle(isMine ? Theme.accentInk : .primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(HomeView.relativeLabel(note.at, now: Date()))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(note.text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(note.displayName)\(isMine ? " (you)" : ""): \(note.text), \(HomeView.relativeLabel(note.at, now: Date()))")
        .accessibilityIdentifier("groups.detail.note.\(note.id)")
        // Taking your own words back is the author's, by rule — so only mine
        // carries the swipe.
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if isMine {
                Button(role: .destructive) {
                    delete(note)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .accessibilityIdentifier("groups.detail.noteDelete.\(note.id)")
            }
        }
    }

    // MARK: - Everyone as mates

    /// Hidden once there is nobody left to ask, so the button never promises
    /// something it won't do. Before `friends()` answers, anyone but me counts.
    private var canAskMates: Bool {
        guard live.isMine, !isLoadingMembers else { return false }
        if let mateIds { return !GroupMateInvite.targets(members, me: profile.id, mates: mateIds).isEmpty }
        return members.contains { $0.id != profile.id }
    }

    private var addMatesLabel: String {
        guard let mateIds else { return "Add everyone as mates" }
        let count = GroupMateInvite.targets(members, me: profile.id, mates: mateIds).count
        return count == 1 ? "Add them as a mate" : "Add all \(count) as mates"
    }

    private var matesSection: some View {
        Section {
            Button {
                addEveryoneAsMates()
            } label: {
                if isAddingMates {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text(addMatesLabel)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .disabled(isAddingMates)
            .accessibilityLabel(addMatesLabel)
            .accessibilityIdentifier("groups.detail.addMates")
        } footer: {
            Text("One request each, and never to someone you're already mates with. Safe to tap twice.")
        }
        .listRowBackground(Theme.surface)
    }

    /// Every group is readable in the app, so a group you are not in already
    /// shows you its name, its tally and its code. Asking you to copy that code
    /// into another sheet was busywork (Tim, 2026-10-03: "make it easier").
    private var joinSection: some View {
        Section {
            Button {
                join()
            } label: {
                if isJoining {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    Text("Join \(live.name)")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .disabled(live.code == nil || isJoining)
            .accessibilityLabel("Join \(live.name)")
            .accessibilityIdentifier("groups.detail.join")
        } footer: {
            Text("Your drinks start counting for this group from now on.")
        }
        .listRowBackground(Theme.surface)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    private func join() {
        guard !isJoining, let code = live.code else { return }
        Haptics.light()
        isJoining = true
        Task {
            let joined = await viewModel.join(code: code)
            isJoining = false
            if joined {
                Haptics.success()
                dismiss()
            }
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
        .listRowBackground(Theme.surface)
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

    private func loadNotes() async {
        do {
            notes = try await groupService.notes(of: group.id)
            notesFailed = false
        } catch {
            notesFailed = true
        }
        isLoadingNotes = false
    }

    /// Left nil when the read fails: then the button says "everyone" and the tap
    /// re-reads the mate list before it sends anything.
    private func loadMateIds() async {
        guard let friendService = appState.friendService else { return }
        if let mates = try? await friendService.friends() { mateIds = Set(mates.map(\.id)) }
    }

    private func sendNote() {
        guard canSendNote, let text = GroupNote.sanitize(noteText) else { return }
        Haptics.light()
        isSendingNote = true
        noteStatus = nil
        Task {
            do {
                try await groupService.postNote(groupId: group.id, text: text, displayName: profile.displayName)
                noteText = ""
                Haptics.success()
                // Re-read rather than guess: the server deletes a note posted
                // inside the 60 s cooldown, and that is not an error — it just
                // means the group never saw this one.
                await loadNotes()
                if !notes.contains(where: { $0.uid == profile.id && $0.text == text }) {
                    noteStatus = "One note a minute — that one didn't stick."
                }
            } catch {
                noteStatus = "Couldn't send that — try again."
            }
            isSendingNote = false
        }
    }

    private func delete(_ note: GroupNote) {
        // The row goes straight away; a refused delete puts the truth back.
        notes.removeAll { $0.id == note.id }
        Task {
            do { try await groupService.deleteNote(groupId: group.id, noteId: note.id) }
            catch { await loadNotes() }
        }
    }

    private func addEveryoneAsMates() {
        guard !isAddingMates, let friendService = appState.friendService else { return }
        Haptics.light()
        isAddingMates = true
        Task {
            defer { isAddingMates = false }
            // Read the mate list at tap time: sending a request to someone who is
            // already a mate would leave a stray request nobody can clear.
            guard let mates = try? await friendService.friends() else {
                mateSummary = "Couldn't check who you're already mates with — try again."
                return
            }
            let mateSet = Set(mates.map(\.id))
            mateIds = mateSet
            var sent = 0, alreadyAsked = 0, failed = 0
            for member in GroupMateInvite.targets(ranking.members, me: profile.id, mates: mateSet) {
                do {
                    try await friendService.sendRequest(to: member.id)
                    sent += 1
                } catch FriendRequestError.alreadyAsked {
                    // A second tap, or a request still waiting to be accepted.
                    // The rules also refuse a block identically, on purpose.
                    alreadyAsked += 1
                } catch {
                    failed += 1
                }
            }
            if sent > 0 { Haptics.success() }
            mateSummary = GroupMateInvite.summary(sent: sent, alreadyAsked: alreadyAsked, failed: failed)
        }
    }

    private var mateSummaryBinding: Binding<Bool> {
        Binding(
            get: { mateSummary != nil },
            set: { if !$0 { mateSummary = nil } }
        )
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
