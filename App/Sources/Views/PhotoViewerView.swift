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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.largeTitle)
                        Text("Photo unavailable")
                            .font(.headline)
                        Text("The link may have expired — signed URLs are short-lived.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white)
                @unknown default:
                    EmptyView()
                }
            }
        }
        .overlay(alignment: .top) {
            header
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

    private var header: some View {
        HStack {
            Text(ownerName)
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            Text("👀 view once")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.2), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
}
