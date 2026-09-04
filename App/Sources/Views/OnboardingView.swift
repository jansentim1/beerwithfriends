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
            if case .needsUsername = appState.phase {
                UsernamePickerStep()
            } else {
                SignInStep()
            }
        }
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
    @State private var currentNonce: String?
    @State private var isSigningIn = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("🍺")
                .font(.system(size: 88))
            Text("Beer With Friends")
                .font(.largeTitle.bold())
            Text("Tap once when you crack open a beer. Your friends get a push and can cheers you back — add a photo they can look at exactly once.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
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
            .disabled(isSigningIn)
            Text("No email, no password — just your Apple ID.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
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

// MARK: - Step 2: Username picker

private struct UsernamePickerStep: View {
    @EnvironmentObject private var appState: AppState
    @State private var username = ""
    @State private var displayName = ""
    @State private var availability: Availability = .idle
    @State private var isClaiming = false

    private enum Availability: Equatable {
        case idle          // empty field
        case invalid       // fails Username.normalize
        case checking
        case available
        case taken
        case unknown       // availability lookup failed (offline etc.)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Pick your username")
                .font(.largeTitle.bold())
            Text("Friends add you by exact username — make it one you can shout across a bar.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .textFieldStyle(.roundedBorder)
                availabilityLabel
            }

            TextField("Display name (optional)", text: $displayName)
                .textFieldStyle(.roundedBorder)

            Button {
                claim()
            } label: {
                Group {
                    if isClaiming {
                        ProgressView()
                    } else {
                        Text("Claim it 🍺")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isClaiming || !(availability == .available || availability == .unknown))

            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .foregroundStyle(.tint)
                Text("One more thing after this: we'll ask permission to send notifications. That's the whole app — you hear the moment a friend cracks one open, they hear when you do.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            Spacer()

            Button("Not you? Sign out") {
                Task { await appState.signOut() }
            }
            .font(.footnote)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        // Debounced live availability: retyping changes the id, which cancels
        // the in-flight check (including its sleep) and starts a new one.
        .task(id: username) {
            await checkAvailability()
        }
    }

    @ViewBuilder
    private var availabilityLabel: some View {
        switch availability {
        case .idle:
            Text("3–15 characters: a–z, 0–9, _ — starts with a letter.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .invalid:
            Label("3–15 characters: a–z, 0–9, _ — starts with a letter.", systemImage: "xmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking…").font(.footnote).foregroundStyle(.secondary)
            }
        case .available:
            Label("Available 🍻", systemImage: "checkmark.circle")
                .font(.footnote)
                .foregroundStyle(.green)
        case .taken:
            Label("Taken — try another.", systemImage: "xmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
        case .unknown:
            Label("Couldn't check availability — you can still try to claim it.", systemImage: "wifi.slash")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
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
