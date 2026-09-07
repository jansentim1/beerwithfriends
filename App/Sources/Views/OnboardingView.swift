import AuthenticationServices
import BeerKit
import CryptoKit
import SwiftUI

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Handles both pre-auth phases: `.signedOut` (Sign in with Apple) and
/// `.needsUsername` (pick a username + notifications explainer).
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .needsUsername:
                UsernamePickerStep()
            case .profileUnavailable:
                ProfileUnavailableStep()
            default:
                SignInStep()
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        .alert("Oops", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )
    }
}

// MARK: - Step 1: Sign in with Apple

private struct SignInStep: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentNonce: String?
    @State private var isSigningIn = false
    @State private var didAppear = false
    /// Theme's display font is a fixed size, so scale it with the reading size
    /// by hand — the wordmark still has to answer to Dynamic Type.
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkSize: CGFloat = 44

    var body: some View {
        // Hero above, thumb-height action below: the scrolling half shrinks as the
        // reading size grows, so the Apple button never walks off the screen.
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer(minLength: 0)
                        hero
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            signInFooter
        }
    }

    private var hero: some View {
        VStack(spacing: 16) {
            Text("🍺")
                .font(.system(size: 64))
                // Reduce Motion: no pop, just the final size. Never animates
                // opacity, so a screenshot taken mid-launch is still complete.
                .scaleEffect(didAppear ? 1 : 0.92)
                .accessibilityHidden(true)
            Text("PubDates")
                .font(Theme.display(wordmarkSize))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityAddTraits(.isHeader)
            Text("Tap when you crack one open — your mates hear it and cheers you back.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            guard !didAppear else { return }
            if reduceMotion {
                didAppear = true
            } else {
                withAnimation(Theme.spring) { didAppear = true }
            }
        }
    }

    private var signInFooter: some View {
        VStack(spacing: 12) {
            SignInWithAppleButton(.signIn) { request in
                // Fresh nonce per attempt: raw goes to Firebase, SHA256 to Apple.
                let nonce = randomNonceString()
                currentNonce = nonce
                request.requestedScopes = [.fullName]
                request.nonce = sha256Hex(nonce)
            } onCompletion: { result in
                handle(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .disabled(isSigningIn)
            .opacity(isSigningIn ? 0.6 : 1)
            .accessibilityIdentifier("signin.apple")
            #if DEBUG
            if EmulatorConfig.isEnabled {
                Button("Sign in (test account)") {
                    Task { await appState.signInForUITests() }
                }
                .buttonStyle(PillButtonStyle(emphasis: .quiet))
                .frame(minHeight: 44)
                .accessibilityIdentifier("signin.test")
            }
            #endif
            Text("No email, no password — just your Apple ID.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce
            else {
                appState.errorMessage = "Sign in failed — try again."
                return
            }
            isSigningIn = true
            Task {
                await appState.signInWithApple(idToken: idToken, nonce: nonce)
                isSigningIn = false
                // On success the auth listener flips `phase`; on failure
                // AppState set `errorMessage` and the alert shows.
            }
        case .failure:
            // User cancelled or a system error — no alert spam, just tap again.
            break
        }
    }
}

/// Cryptographically random nonce from a 64-character set (uniform — no
/// modulo bias), per Firebase's Sign in with Apple guidance.
private func randomNonceString(length: Int = 32) -> String {
    let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_")
    precondition(charset.count == 64)
    var bytes = [UInt8](repeating: 0, count: length)
    let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    precondition(status == errSecSuccess, "Unable to generate a secure nonce")
    return String(bytes.map { charset[Int($0 & 0x3F)] })
}

private func sha256Hex(_ input: String) -> String {
    SHA256.hash(data: Data(input.utf8))
        .map { String(format: "%02x", $0) }
        .joined()
}

// MARK: - Recovery: signed in, profile unreachable

private struct ProfileUnavailableStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var isRetrying = false
    @ScaledMetric(relativeTo: .title2) private var titleSize: CGFloat = 28

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        Spacer(minLength: 0)
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 88, height: 88)
                            .background(Theme.accentSoft, in: Circle())
                            .accessibilityHidden(true)
                        Text("Couldn't load your profile")
                            .font(Theme.display(titleSize))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("You're signed in, but we couldn't reach the server. Check your connection and try again.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            VStack(spacing: 12) {
                Button {
                    isRetrying = true
                    Task {
                        await appState.retryLoadProfile()
                        isRetrying = false
                    }
                } label: {
                    if isRetrying {
                        ProgressView()
                            .tint(Theme.onAccent)
                    } else {
                        Text("Try again")
                    }
                }
                .buttonStyle(HeroButtonStyle())
                .disabled(isRetrying)
                .opacity(isRetrying ? 0.7 : 1)
                .accessibilityLabel("Try again")

                Button("Sign out") {
                    Task { await appState.signOut() }
                }
                .font(.subheadline)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Step 2: Username picker

private struct UsernamePickerStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var username = ""
    @State private var displayName = ""
    @State private var availability: Availability = .idle
    @State private var isClaiming = false
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 34

    private enum Availability: Equatable {
        case idle          // empty field
        case invalid       // fails Username.normalize
        case checking
        case available
        case taken
        case unknown       // availability lookup failed (offline etc.)
    }

    private var canClaim: Bool {
        !isClaiming && (availability == .available || availability == .unknown)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pick your username")
                        .font(Theme.display(titleSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("Friends add you by exact username — make it one you can shout across a bar.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    fieldSurface {
                        HStack(spacing: 4) {
                            Text("@")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            TextField("username", text: $username)
                                .accessibilityIdentifier("onboarding.username")
                                .accessibilityLabel("Username")
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.asciiCapable)
                        }
                    }
                    availabilityLabel
                        .animation(Theme.quick, value: availability)
                }

                fieldSurface {
                    TextField("Display name (optional)", text: $displayName)
                        .accessibilityLabel("Display name, optional")
                }

                Button {
                    Haptics.light()
                    claim()
                } label: {
                    if isClaiming {
                        ProgressView()
                            .tint(Theme.onAccent)
                    } else {
                        Text("Claim it 🍺")
                    }
                }
                .buttonStyle(HeroButtonStyle())
                .accessibilityIdentifier("onboarding.claim")
                .accessibilityLabel("Claim it")
                .disabled(!canClaim)
                .opacity(canClaim ? 1 : 0.5)
                .animation(Theme.quick, value: canClaim)

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: "bell.badge.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                    Text("Next: we'll ask permission to send notifications. That's the whole app — you hear the moment a mate cracks one open, they hear when you do.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Button("Not you? Sign out") {
                    Task { await appState.signOut() }
                }
                .font(.subheadline)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        // Debounced live availability: retyping changes the id, which cancels
        // the in-flight check (including its sleep) and starts a new one.
        .task(id: username) {
            await checkAvailability()
        }
    }

    /// Rounded card that holds a text field (Theme.surface, cardRadius).
    private func fieldSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.body)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.surface)
            )
    }

    @ViewBuilder
    private var availabilityLabel: some View {
        Group {
            switch availability {
            case .idle:
                Text("3–15 characters: a–z, 0–9, _ — starts with a letter.")
                    .foregroundStyle(.secondary)
            case .invalid:
                Label("3–15 characters: a–z, 0–9, _ — starts with a letter.", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case .checking:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking…").foregroundStyle(.secondary)
                }
            case .available:
                Label("Available 🍻", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
            case .taken:
                Label("Taken — try another.", systemImage: "xmark.circle")
                    .foregroundStyle(.red)
            case .unknown:
                Label("Couldn't check availability — you can still try to claim it.", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            }
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func checkAvailability() async {
        guard !username.isEmpty else {
            availability = .idle
            return
        }
        guard let normalized = Username.normalize(username) else {
            availability = .invalid
            return
        }
        availability = .checking
        try? await Task.sleep(for: .milliseconds(400)) // debounce window
        guard !Task.isCancelled else { return }
        let taken = await appState.isUsernameTaken(normalized)
        guard !Task.isCancelled else { return }
        switch taken {
        case .some(true): availability = .taken
        case .some(false): availability = .available
        case .none: availability = .unknown
        }
    }

    private func claim() {
        isClaiming = true
        Task {
            // AppState normalizes, claims, and flips phase to .ready on success;
            // on failure it sets errorMessage (shown by OnboardingView's alert).
            await appState.claimUsername(username, displayName: displayName)
            isClaiming = false
        }
    }
}
