import SwiftUI
import UIKit

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Full-screen, once-only photo display, inside a `ScreenshotShield`. The viewer
/// opens the instant the pill is tapped and fetches the bytes itself via `load`
/// (the `getPhotoOnce` round trip), so the tap answers at once instead of after
/// the network (Tim, 2026-11-04: "now there is lag"). Once `load` has run the
/// view is consumed — closing is final (except for the owner, exempt server-side).
/// Tap or swipe down to dismiss; a failure (already viewed, expired, offline)
/// shows in place, with the same way out.
/// A screenshot fires `screenshotReporter(beerId)` (best-effort write of
/// `beers/{beerId}/screenshots/{me}` so the owner can see who screengrabbed).
struct PhotoViewerView: View {
    /// Fetches the photo to a temp file, or says why it could not.
    let load: @MainActor @Sendable () async -> PhotoLoad
    let ownerName: String
    /// Drawn into the photo already; carried as text so VoiceOver can read it.
    var caption: String?
    let beerId: String
    let screenshotReporter: @Sendable (String) async -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0
    /// The photo, once fetched and decoded.
    @State private var loaded: Loaded = .loading
    /// The temp file `load` wrote; removed when the viewer goes.
    @State private var fileURL: URL?

    private enum Loaded { case loading, image(UIImage), failed(String) }

    /// A tap or swipe while the fetch is still running would burn the one view
    /// on a photo never seen; only the close circle works until it is in.
    private var isLoading: Bool {
        if case .loading = loaded { return true }
        return false
    }

    /// Raised when a screenshot is actually taken, so the black rectangle the
    /// viewer just saved is explained rather than mysterious.
    @State private var didScreenshot = false

    /// How far through a swipe-to-dismiss we are, 0…1.
    private var dragProgress: Double {
        min(max(Double(dragOffset), 0) / 400, 1)
    }

    /// The photo and its chrome dim into the black backdrop as the drag runs on,
    /// so letting go reads as "it's already leaving".
    private var contentOpacity: Double {
        1 - dragProgress * 0.5
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Inside a screenshot shield: a screenshot or recording of this
            // screen shows a black frame where the photo is.
            Group {
                switch loaded {
                case .loading:
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .accessibilityLabel("Loading photo")
                case .image(let image):
                    ScreenshotShield(image: image)
                        .ignoresSafeArea()
                        .accessibilityLabel(
                            caption.map { "Photo from \(ownerName): \($0)" } ?? "Photo from \(ownerName)"
                        )
                case .failed(let message):
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Photo unavailable")
                            .font(.headline)
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .foregroundStyle(.white)
                }
            }
            .opacity(contentOpacity)
        }
        .overlay(alignment: .bottom) {
            screenshotNotice
                .opacity(contentOpacity)
        }
        .overlay(alignment: .top) {
            // A filled photo can be light where the header sits: a soft scrim
            // keeps the white name, pill and close circle legible on any photo.
            header
                .padding(.bottom, 56)
                .background(
                    LinearGradient(
                        colors: [.black.opacity(0.45), .black.opacity(0)],
                        startPoint: .top, endPoint: .bottom
                    )
                    .ignoresSafeArea(edges: .top)
                )
                .opacity(contentOpacity)
        }
        .offset(y: max(0, dragOffset))
        .contentShape(Rectangle())
        .onTapGesture {
            if !isLoading { close() }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isLoading { dragOffset = value.translation.height }
                }
                .onEnded { value in
                    if !isLoading, value.translation.height > 120 {
                        close()
                    } else {
                        withAnimation(.snappy) { dragOffset = 0 }
                    }
                }
        )
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)
        ) { _ in
            // Fire-and-forget: the owner gets a screenshot receipt.
            let report = screenshotReporter
            let id = beerId
            Task { await report(id) }
            withAnimation(Theme.quick) { didScreenshot = true }
        }
        .statusBarHidden()
        .task {
            let url: URL
            switch await load() {
            case .file(let fetched): url = fetched
            case .failed(let message):
                loaded = .failed(message)
                return
            }
            fileURL = url
            // Off the main actor: the file is a downscaled JPEG, but decoding
            // still should not block the presentation animation.
            let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return UIImage(data: data)
            }.value
            loaded = image.map { .image($0) } ?? .failed("It could not be read — try again from the feed.")
        }
    }

    /// View-once: the temp file goes with the viewer.
    private func close() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        onDismiss()
    }

    /// Says before the fact, and again after it, that a screenshot of this screen
    /// saves a black rectangle (Tim, 2026-09-26). Without it someone screenshots,
    /// finds a black image later, and assumes the app is broken — and the owner
    /// gets a receipt for an attempt the viewer never understood they made.
    private var screenshotNotice: some View {
        Text(didScreenshot
             ? "That screenshot came out black — and \(ownerName) was told."
             : "Screenshots of this photo come out black.")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.white.opacity(didScreenshot ? 0.28 : 0.18), in: Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .accessibilityIdentifier("photo.screenshotNotice")
    }

    /// Whose beer this is, that it is a one-look photo, and the way out.
    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(name: ownerName, size: 36)

            Text(ownerName)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("👀 View once")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 28)
                .background(.white.opacity(0.18), in: Capsule())
                .accessibilityLabel("View once")

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.18), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
}

/// What `PhotoViewerView.load` comes back with: the JPEG on disk, or the
/// sentence to show instead ("You already used your one view 👀", …).
enum PhotoLoad: Sendable {
    case file(URL)
    case failed(String)
}
