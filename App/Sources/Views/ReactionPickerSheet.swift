import BeerKit
import SwiftUI

/// Sending a reaction back on a mate's drink: six presets, any other emoji, or a
/// few words of your own (Tim, 2026-09-18: "emojis for custom should be free but
/// text then custom"). One per mate per drink, which is what the rules enforce,
/// so this closes as soon as something is sent.
struct ReactionPickerSheet: View {
    let ownerName: String
    /// True once you have cheersed this drink: the 🍻 tile goes quiet rather
    /// than disappearing, so the row of options keeps its shape.
    let hasCheersed: Bool
    /// True once you have sent a reaction to this drink. The server allows one
    /// per mate per drink, so everything but 🍻 goes quiet the same way — before
    /// this the tiles stayed live, buzzed, and sent nothing.
    let alreadyReacted: Bool
    /// Called with the raw text, or "🍻" for a cheers; the parent routes it.
    let onSend: (String) -> Void
    /// Opens the list of who already reacted.
    let onSeeWho: () -> Void

    /// Cheers first — it is the one everyone reaches for, and the pill that
    /// opens this sheet is the 🍻 pill (Tim, 2026-10-03: pressing it should
    /// open the options, not just send a like).
    private var tiles: [String] { [Reaction.cheers] + Reaction.presets }

    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @FocusState private var fieldFocused: Bool

    private var trimmed: String? { Reaction.normalize(custom) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Say something back")
                            .font(Theme.displayTitle2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        // Quiet tiles with no reason given read as broken.
                        if alreadyReacted {
                            Text(hasCheersed
                                 ? "You already reacted and cheersed this one — one of each is the limit."
                                 : "You already reacted to this one. You can still cheers it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    // The quick way: one tap, sheet closes.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                              spacing: 10) {
                        ForEach(tiles, id: \.self) { emoji in
                            let isCheers = emoji == Reaction.cheers
                            let spent = isCheers ? hasCheersed : alreadyReacted
                            Button {
                                send(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 30))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .background(
                                        spent ? AnyShapeStyle(Color(.tertiarySystemFill))
                                              : AnyShapeStyle(Theme.accentSoft),
                                        in: RoundedRectangle(cornerRadius: Theme.cardRadius,
                                                             style: .continuous))
                                    .opacity(spent ? 0.5 : 1)
                            }
                            .buttonStyle(.plain)
                            .disabled(spent)
                            .accessibilityLabel(spent
                                                ? (isCheers ? "Already cheersed" : "Already reacted")
                                                : "React with \(emoji)")
                            .accessibilityIdentifier("reaction.preset.\(emoji)")
                        }
                    }

                    // The custom way: the emoji keyboard is one tap away in the
                    // same field, so "any emoji" and "a few words" are one control.
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Any emoji, or a few words", text: $custom)
                            .focused($fieldFocused)
                            .font(.body)
                            .submitLabel(.send)
                            .onSubmit { if let trimmed { send(trimmed) } }
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Theme.cardRadius,
                                                         style: .continuous).fill(Theme.surface))
                            .accessibilityIdentifier("reaction.custom")
                            .accessibilityLabel("Custom reaction")
                            .disabled(alreadyReacted)
                            .opacity(alreadyReacted ? 0.5 : 1)
                        if !alreadyReacted {
                            Text("Up to \(Reaction.maxLength) characters. \(ownerName) sees it on their drink.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 4)
                        }
                    }

                    let sendDisabled = trimmed == nil || alreadyReacted
                    Button {
                        if let trimmed { send(trimmed) }
                    } label: {
                        Text("Send")
                    }
                    .buttonStyle(HeroButtonStyle())
                    .disabled(sendDisabled)
                    .opacity(sendDisabled ? 0.5 : 1)
                    .animation(Theme.quick, value: sendDisabled)
                    .accessibilityIdentifier("reaction.send")

                    Button {
                        Haptics.light()
                        // The names open from this sheet's `onDismiss`: two
                        // sibling sheets handing over while the first is still
                        // presented is the tap that does nothing.
                        onSeeWho()
                        dismiss()
                    } label: {
                        Text("See who reacted")
                    }
                    .buttonStyle(PillButtonStyle(emphasis: .quiet))
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("reaction.seeWho")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func send(_ raw: String) {
        // The quiet controls are the signal; this is the belt that stops a stale
        // keyboard submit from buzzing success and sending nothing.
        let spent = raw == Reaction.cheers ? hasCheersed : alreadyReacted
        guard !spent else { return }
        Haptics.light()
        onSend(raw)
        dismiss()
    }
}
