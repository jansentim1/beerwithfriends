import BeerKit
import SwiftUI

/// Who cheersed a drink, and who quick-replied (Tim, 2026-09-16: "i want to see
/// who liked"). Names come from the server mirrors on the beer doc, so this
/// opens on data the feed already has — no read, no spinner. It reads the live
/// feed, so a cheers that lands while the sheet is open appears in place.
struct ReactionsSheet: View {
    let beer: BeerLog
    /// The owner's name as the row shows it ("You" on your own drink).
    let ownerLabel: String

    @Environment(\.dismiss) private var dismiss

    private var reactions: Reactions { beer.reactions }

    var body: some View {
        NavigationStack {
            Group {
                if reactions.isEmpty {
                    emptyState
                } else {
                    List {
                        if !reactions.cheers.isEmpty {
                            Section {
                                ForEach(reactions.cheers) { row($0) }
                            } header: {
                                Eyebrow(text: "Cheers")
                            }
                            .listRowBackground(Theme.surface)
                        }
                        if !reactions.replies.isEmpty {
                            Section {
                                ForEach(reactions.replies) { row($0) }
                            } header: {
                                Eyebrow(text: "Replies")
                            }
                            .listRowBackground(Theme.surface)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Theme.ground.ignoresSafeArea())
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("reactions.done")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// "🍻 3" reads as the tally it is; the drink and whose it is sit under it
    /// in the list, not in a long title.
    private var title: String {
        reactions.cheers.isEmpty ? "Reactions" : "🍻 \(reactions.cheersCount)"
    }

    /// One mate: avatar, name, and the emoji they sent — a cheers is 🍻, a quick
    /// reply is its own. Every row says what came back (Tim, 2026-09-18: "only
    /// responded with emojis"), so the emoji carries it and the words are left
    /// to VoiceOver.
    private func row(_ reactor: Reactor) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: reactor.name, size: 44)
            Text(reactor.name)
                .font(.headline)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            // A cheers is 🍻; anything else is what that mate actually sent,
            // emoji or words, so the sheet is where the full text lives.
            Text(reactor.reply ?? "🍻")
                .font(Reaction.isAllEmoji(reactor.reply ?? "🍻") ? .title3 : .subheadline)
                .foregroundStyle(reactor.reply.map { Reaction.isAllEmoji($0) } == false
                                 ? Color.secondary : .primary)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            reactor.reply.map { "\(reactor.name) reacted \($0)" } ?? "\(reactor.name) cheersed"
        )
    }

    /// Reachable from the long-press menu before anyone has reacted.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("No cheers yet")
                .font(Theme.displayTitle2)
            Text("\(ownerLabel == "You" ? "Your" : "\(ownerLabel)'s") \(beer.drink.label.lowercased()) hasn't been cheersed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.ground.ignoresSafeArea())
        .accessibilityElement(children: .combine)
    }
}
