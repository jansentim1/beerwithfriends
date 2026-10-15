import BeerKit
import SwiftUI

/// Where you are, typed, when PubDates may not read your location (Tim,
/// 2026-10-15: "add a typed place when no location setting"). Replaces the
/// old "PubDates needs your location" dead end: App Review 5.1.1(iv) asks for
/// a manual place when Location is declined. The typed text goes on the drink
/// as its place, with no coordinate, so it never gets a map pin.
struct TypedPlaceSheet: View {
    /// Called with the normalized place; the parent carries on to the camera.
    let onPost: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var fieldFocused: Bool

    private var place: String? { TypedPlace.normalize(text) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Where are you?")
                            .font(Theme.displayTitle2)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("Your mates see this on your drink. No pin on the map.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    TextField("Café De Zon, Amsterdam", text: $text)
                        .focused($fieldFocused)
                        .font(.body)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { post() }
                        .onChange(of: text) { _, new in
                            let clamped = TypedPlace.clampWhileTyping(new)
                            if clamped != new { text = clamped }
                        }
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Theme.cardRadius,
                                                     style: .continuous).fill(Theme.surface))
                        .accessibilityIdentifier("typedPlace.field")
                        .accessibilityLabel("Where you are")

                    let postDisabled = place == nil
                    Button {
                        post()
                    } label: {
                        Text("Post")
                    }
                    .buttonStyle(HeroButtonStyle())
                    .disabled(postDisabled)
                    .opacity(postDisabled ? 0.5 : 1)
                    .animation(Theme.quick, value: postDisabled)
                    .accessibilityIdentifier("typedPlace.post")

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        dismiss()
                    } label: {
                        Text("Use my location instead")
                    }
                    .buttonStyle(PillButtonStyle(emphasis: .quiet))
                    .frame(minHeight: 44)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("typedPlace.useLocation")
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
        .onAppear { fieldFocused = true }
    }

    private func post() {
        guard let place else { return }
        Haptics.light()
        onPost(place)
        dismiss()
    }
}
