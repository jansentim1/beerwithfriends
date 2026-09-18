import BeerKit
import SwiftUI

/// Sending a reaction back on a mate's drink: six presets, any other emoji, or a
/// few words of your own (Tim, 2026-09-18: "emojis for custom should be free but
/// text then custom"). One per mate per drink, which is what the rules enforce,
/// so this closes as soon as something is sent.
struct ReactionPickerSheet: View {
    let ownerName: String
    /// Called with the raw text; the view model normalizes and sends.
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""
    @FocusState private var fieldFocused: Bool

    private var trimmed: String? { Reaction.normalize(custom) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Say something back")
                        .font(Theme.displayTitle2)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    // The quick way: one tap, sheet closes.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                              spacing: 10) {
                        ForEach(Reaction.presets, id: \.self) { emoji in
                            Button {
                                send(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 30))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 60)
                                    .background(Theme.accentSoft, in: RoundedRectangle(
                                        cornerRadius: Theme.cardRadius, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("React with \(emoji)")
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
                        Text("Up to \(Reaction.maxLength) characters. \(ownerName) sees it on their drink.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }

                    Button {
                        if let trimmed { send(trimmed) }
                    } label: {
                        Text("Send")
                    }
                    .buttonStyle(HeroButtonStyle())
                    .disabled(trimmed == nil)
                    .opacity(trimmed == nil ? 0.5 : 1)
                    .animation(Theme.quick, value: trimmed == nil)
                    .accessibilityIdentifier("reaction.send")
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
        Haptics.light()
        onSend(raw)
        dismiss()
    }
}
