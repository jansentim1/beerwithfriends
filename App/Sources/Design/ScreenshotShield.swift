import SwiftUI
import UIKit

/// Shows an image inside the drawing canvas of a secure `UITextField`. iOS blanks
/// that canvas in screenshots, screen recordings and mirroring, so a view-once
/// photo captured this way is a black rectangle (Tim, 2026-09-11: "foto's mogen
/// niet gescreenshot kunnen worden"). The screenshot receipt to the owner still
/// fires from `UIApplication.userDidTakeScreenshotNotification`.
///
/// Relies on the text field's private layout canvas being its first subview,
/// which has held since iOS 15 and is what every "screen shield" library does;
/// if the canvas is ever missing, the image simply shows unshielded.
struct ScreenshotShield: UIViewRepresentable {
    let image: UIImage
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> UIView {
        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false
        field.backgroundColor = .clear
        field.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: image)
        imageView.contentMode = contentMode
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.isAccessibilityElement = false

        guard let canvas = field.subviews.first else {
            return imageView
        }
        canvas.subviews.forEach { $0.removeFromSuperview() }
        canvas.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(imageView)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            canvas.trailingAnchor.constraint(equalTo: field.trailingAnchor),
            canvas.topAnchor.constraint(equalTo: field.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: field.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: canvas.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        return field
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let imageView = uiView as? UIImageView ?? uiView.subviews.first?.subviews.first as? UIImageView
        imageView?.image = image
    }
}
