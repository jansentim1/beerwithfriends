import SwiftUI
import UIKit

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Full-screen, once-only photo display. The signed URL was already consumed
/// via `getPhotoOnce` before this view appears — closing it is final (except
/// for the owner, who is exempt server-side). Tap or swipe down to dismiss.
/// A screenshot fires `screenshotReporter(beerId)` (best-effort write of
/// `beers/{beerId}/screenshots/{me}` so the owner can see who screengrabbed).
struct PhotoViewerView: View {
    let url: URL
    let ownerName: String
    let beerId: String
    let screenshotReporter: @Sendable (String) async -> Void
    let onDismiss: () -> Void

    @State private var dragOffset: CGFloat = 0

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

            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                        .accessibilityLabel("Loading photo")
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel("Photo from \(ownerName)")
                case .failure:
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.7))
                        Text("Photo unavailable")
                            .font(.headline)
                        Text("The link may have expired — signed URLs are short-lived.")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 32)
                    .foregroundStyle(.white)
                @unknown default:
                    EmptyView()
                }
            }
            .opacity(contentOpacity)
        }
        .overlay(alignment: .top) {
            header
                .opacity(contentOpacity)
        }
        .offset(y: max(0, dragOffset))
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    if value.translation.height > 120 {
                        onDismiss()
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
        }
        .statusBarHidden()
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

            Button(action: onDismiss) {
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
