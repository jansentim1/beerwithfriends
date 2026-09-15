import SwiftUI
import UIKit

/// Shows an image inside the drawing canvas of a secure `UITextField`. iOS blanks
/// that canvas in screenshots, screen recordings and mirroring, so a view-once
/// photo captured this way is a black rectangle (Tim, 2026-09-11: "foto's mogen
/// niet gescreenshot kunnen worden"). The screenshot receipt to the owner still
/// fires from `UIApplication.userDidTakeScreenshotNotification`.
///
/// The canvas is lifted OUT of the text field into a plain container view, the
/// way the screen-shield libraries do it: left inside, the field's own layout
/// keeps re-sizing the canvas to its text rect and the photo came out scaled
/// (testers, build 22: "foto's zijn ingezoomd"). The canvas keeps its secure
/// rendering wherever it lives, as long as the field stays alive.
struct ScreenshotShield: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> ShieldContainer {
        let container = ShieldContainer()
        container.imageView.image = image
        container.imageView.contentMode = contentMode
        return container
    }

    func updateUIView(_ uiView: ShieldContainer, context: Context) {
        uiView.imageView.image = image
        uiView.imageView.contentMode = contentMode
    }

    final class ShieldContainer: UIView {
        /// Kept alive: the canvas belongs to it.
        private let field = UITextField()
        let imageView = UIImageView()

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            field.isSecureTextEntry = true
            field.isUserInteractionEnabled = false
            imageView.clipsToBounds = true
            imageView.isAccessibilityElement = false
            imageView.translatesAutoresizingMaskIntoConstraints = false

            // The private layout canvas is the field's first subview (iOS 15+).
            // If that ever changes, the photo shows unshielded rather than not at all.
            let host: UIView
            if let canvas = field.subviews.first {
                canvas.subviews.forEach { $0.removeFromSuperview() }
                canvas.removeFromSuperview()
                canvas.translatesAutoresizingMaskIntoConstraints = false
                canvas.backgroundColor = .clear
                addSubview(canvas)
                NSLayoutConstraint.activate([
                    canvas.leadingAnchor.constraint(equalTo: leadingAnchor),
                    canvas.trailingAnchor.constraint(equalTo: trailingAnchor),
                    canvas.topAnchor.constraint(equalTo: topAnchor),
                    canvas.bottomAnchor.constraint(equalTo: bottomAnchor),
                ])
                host = canvas
            } else {
                host = self
            }
            host.addSubview(imageView)
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: host.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            ])
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }
}
