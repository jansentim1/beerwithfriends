import AVFoundation
import BeerKit
import SwiftUI
import UIKit

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Live camera capture — the ONLY photo source (no photo-library access, by
/// design: beer photos are taken in the moment). Back camera by default with a
/// flip button; shutter → retake / use-photo review. Returns a JPEG downscaled
/// to ≤ 1080px on the long edge at 0.8 quality via `onCapture`, then dismisses.
struct CameraView: UIViewControllerRepresentable {
    /// The JPEG (caption already drawn into it) and the caption as text, which
    /// travels separately so VoiceOver can read a captioned photo.
    let onCapture: (Data, String?) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CameraCaptureViewController {
        let controller = CameraCaptureViewController()
        let onCapture = self.onCapture
        let dismiss = self.dismiss
        controller.onUsePhoto = { data, caption in
            onCapture(data, caption)
            dismiss()
        }
        controller.onCancel = { dismiss() }
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraCaptureViewController, context: Context) {}
}

// MARK: - View controller

/// Full-bleed preview with the iOS camera idiom on top: a white ring shutter
/// centred above the home indicator, glass circles for cancel and flip, and a
/// Retake / Use-photo pair in review. See docs/design/direction.md, screen 3.
final class CameraCaptureViewController: UIViewController {
    var onUsePhoto: ((Data, String?) -> Void)?
    var onCancel: (() -> Void)?

    private let camera = CameraSessionController()
    private var position: AVCaptureDevice.Position = .back
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Retains the in-flight capture delegate (AVCapturePhotoOutput doesn't).
    private var pendingDelegate: PhotoCaptureDelegate?
    private var capturedImage: UIImage?
    private let shutterHaptic = UIImpactFeedbackGenerator(style: .medium)
    /// Where the strip sits, 0…1 down the photo. Dragged, then remembered for
    /// the next shot in this session.
    private var captionCentre: CGFloat = CaptionLayout.defaultCentre

    // MARK: Metrics and palette

    private static let glassDiameter: CGFloat = 48
    private static let shutterDiameter: CGFloat = 72
    private static let shutterCoreDiameter: CGFloat = 60
    private static let shutterRing: CGFloat = 4
    private static let pairHeight: CGFloat = 52

    /// "Pint amber", mirroring `Theme.accent` (UIKit can't read the SwiftUI Color).
    /// Computed, not stored: a `static let` of a non-Sendable UIKit type trips
    /// Swift 6 strict concurrency.
    private static var accent: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 1.00, green: 0.655, blue: 0.20, alpha: 1)
                : UIColor(red: 0.90, green: 0.54, blue: 0.00, alpha: 1)
        }
    }
    /// Ink on top of the accent — always dark, mirroring `Theme.onAccent`.
    private static var onAccent: UIColor { UIColor(red: 0.16, green: 0.09, blue: 0.0, alpha: 1) }

    // Live controls
    private let shutterButton = UIButton(type: .custom)
    private let shutterCore = UIView()
    private let flipButton = UIButton(type: .system)
    private let flipBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let cancelButton = UIButton(type: .system)
    private let cancelBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    // Review controls
    private let previewImageView = UIImageView()
    private let retakeButton = UIButton(type: .system)
    private let retakeBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let usePhotoButton = UIButton(type: .system)
    // Caption ("van die snapchat stroken"): a flat band you type on and drag.
    private let captionStrip = UIView()
    private let captionTextView = UITextView()
    private let captionButton = UIButton(type: .system)
    private let captionBackdrop = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private var captionCentreConstraint: NSLayoutConstraint?
    private var captionBottomConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // The viewfinder is a black room in both schemes; keep materials and the
        // amber accent tuned for it.
        overrideUserInterfaceStyle = .dark
        buildControls()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor [weak self] in
                    if granted {
                        self?.startCamera()
                    } else {
                        self?.showPermissionDenied()
                    }
                }
            }
        default: // .denied, .restricted
            showPermissionDenied()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        layoutCaption()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camera.stop()
    }

    // MARK: UI

    private func buildControls() {
        // Glass circles, Camera-app idiom: cancel leading, flip trailing.
        configureGlassCircle(
            cancelButton, in: cancelBackdrop, symbol: "xmark",
            label: "Cancel", action: #selector(cancelTapped)
        )
        configureGlassCircle(
            flipButton, in: flipBackdrop, symbol: "arrow.triangle.2.circlepath.camera",
            label: "Flip camera", action: #selector(flipTapped)
        )

        // Shutter: a 4 pt white ring around a 60 pt white disc.
        shutterButton.backgroundColor = .clear
        shutterButton.layer.cornerRadius = Self.shutterDiameter / 2
        shutterButton.layer.borderWidth = Self.shutterRing
        shutterButton.layer.borderColor = UIColor.white.cgColor
        shutterButton.accessibilityLabel = "Take photo"
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        shutterButton.addTarget(self, action: #selector(shutterPressed), for: [.touchDown, .touchDragEnter])
        shutterButton.addTarget(
            self, action: #selector(shutterReleased),
            for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit]
        )

        shutterCore.backgroundColor = .white
        shutterCore.layer.cornerRadius = Self.shutterCoreDiameter / 2
        shutterCore.isUserInteractionEnabled = false
        shutterCore.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.addSubview(shutterCore)

        // Fill, matching the live preview's framing: no jump from preview to review.
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        previewImageView.backgroundColor = .black
        previewImageView.isHidden = true
        previewImageView.isAccessibilityElement = true
        previewImageView.accessibilityLabel = "Captured photo"

        // Review pair: glass "Retake" on the left, amber "Use photo" on the right.
        var retakeConfig = UIButton.Configuration.plain()
        retakeConfig.title = "Retake"
        retakeConfig.baseForegroundColor = .white
        retakeConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24)
        retakeConfig.titleTextAttributesTransformer = Self.headlineTitle
        retakeButton.configuration = retakeConfig
        retakeButton.accessibilityLabel = "Retake"
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
        embed(retakeButton, in: retakeBackdrop, cornerRadius: Self.pairHeight / 2)
        retakeBackdrop.isHidden = true

        var useConfig = UIButton.Configuration.filled()
        useConfig.title = "Use photo"
        useConfig.baseBackgroundColor = Self.accent
        useConfig.baseForegroundColor = Self.onAccent
        useConfig.cornerStyle = .capsule
        useConfig.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24)
        useConfig.titleTextAttributesTransformer = Self.headlineTitle
        usePhotoButton.configuration = useConfig
        usePhotoButton.accessibilityLabel = "Use photo"
        usePhotoButton.isHidden = true
        usePhotoButton.addTarget(self, action: #selector(usePhotoTapped), for: .touchUpInside)

        buildCaption()

        for control in [previewImageView, cancelBackdrop, flipBackdrop, shutterButton, retakeBackdrop, usePhotoButton] {
            control.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(control)
        }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: view.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            cancelBackdrop.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            cancelBackdrop.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            cancelBackdrop.widthAnchor.constraint(equalToConstant: Self.glassDiameter),
            cancelBackdrop.heightAnchor.constraint(equalToConstant: Self.glassDiameter),

            flipBackdrop.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            flipBackdrop.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            flipBackdrop.widthAnchor.constraint(equalToConstant: Self.glassDiameter),
            flipBackdrop.heightAnchor.constraint(equalToConstant: Self.glassDiameter),

            // The caption button takes the flip button's corner in review.
            captionBackdrop.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            captionBackdrop.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            captionBackdrop.widthAnchor.constraint(equalToConstant: Self.glassDiameter),
            captionBackdrop.heightAnchor.constraint(equalToConstant: Self.glassDiameter),

            captionStrip.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            captionStrip.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            captionTextView.leadingAnchor.constraint(equalTo: captionStrip.leadingAnchor, constant: 20),
            captionTextView.trailingAnchor.constraint(equalTo: captionStrip.trailingAnchor, constant: -20),
            captionTextView.topAnchor.constraint(equalTo: captionStrip.topAnchor, constant: 12),
            captionTextView.bottomAnchor.constraint(equalTo: captionStrip.bottomAnchor, constant: -12),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: Self.shutterDiameter),
            shutterButton.heightAnchor.constraint(equalToConstant: Self.shutterDiameter),

            shutterCore.centerXAnchor.constraint(equalTo: shutterButton.centerXAnchor),
            shutterCore.centerYAnchor.constraint(equalTo: shutterButton.centerYAnchor),
            shutterCore.widthAnchor.constraint(equalToConstant: Self.shutterCoreDiameter),
            shutterCore.heightAnchor.constraint(equalToConstant: Self.shutterCoreDiameter),

            retakeBackdrop.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            retakeBackdrop.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24),
            retakeBackdrop.heightAnchor.constraint(equalToConstant: Self.pairHeight),

            usePhotoButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            usePhotoButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24),
            usePhotoButton.heightAnchor.constraint(equalToConstant: Self.pairHeight),
            usePhotoButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: retakeBackdrop.trailingAnchor, constant: 16
            ),
        ])

        // Comfortable minimum widths, but breakable: on a 320 pt screen at a large
        // reading size the titles win over the pair's preferred proportions.
        let minimumWidths: [(UIView, CGFloat)] = [(retakeBackdrop, 104), (usePhotoButton, 132)]
        for (control, width) in minimumWidths {
            let minWidth = control.widthAnchor.constraint(greaterThanOrEqualToConstant: width)
            minWidth.priority = .defaultLow
            minWidth.isActive = true
        }
    }

    /// Titles follow Dynamic Type (Headline) rather than a hard-coded size.
    private static var headlineTitle: UIConfigurationTextAttributesTransformer {
        UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = UIFont.preferredFont(forTextStyle: .headline)
            return outgoing
        }
    }

    /// A 48 pt circular SF Symbol control on an ultra-thin dark blur.
    private func configureGlassCircle(
        _ button: UIButton, in backdrop: UIVisualEffectView,
        symbol: String, label: String, action: Selector
    ) {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        config.baseForegroundColor = .white
        config.contentInsets = .zero
        button.configuration = config
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        embed(button, in: backdrop, cornerRadius: Self.glassDiameter / 2)
    }

    /// Puts the control inside the blur's `contentView` so touches still land on
    /// it, and rounds the material to the given radius.
    private func embed(_ button: UIButton, in backdrop: UIVisualEffectView, cornerRadius: CGFloat) {
        backdrop.layer.cornerRadius = cornerRadius
        backdrop.layer.cornerCurve = .continuous
        backdrop.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        backdrop.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: backdrop.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: backdrop.contentView.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: backdrop.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: backdrop.contentView.trailingAnchor),
        ])
    }

    // MARK: - Caption

    private func buildCaption() {
        captionStrip.backgroundColor = UIColor.black.withAlphaComponent(CaptionLayout.stripOpacity)
        captionStrip.isHidden = true
        captionStrip.translatesAutoresizingMaskIntoConstraints = false

        captionTextView.backgroundColor = .clear
        captionTextView.textColor = .white
        captionTextView.tintColor = Self.accent
        captionTextView.font = .systemFont(ofSize: 20, weight: .semibold)
        captionTextView.textAlignment = .center
        captionTextView.isScrollEnabled = false
        captionTextView.textContainerInset = .zero
        captionTextView.textContainer.lineFragmentPadding = 0
        captionTextView.returnKeyType = .done
        captionTextView.delegate = self
        captionTextView.accessibilityIdentifier = "camera.caption"
        captionTextView.accessibilityLabel = "Caption"
        captionTextView.translatesAutoresizingMaskIntoConstraints = false

        var config = UIButton.Configuration.plain()
        config.title = "Aa"
        config.baseForegroundColor = .white
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 17, weight: .bold)
            return out
        }
        captionButton.configuration = config
        captionButton.accessibilityLabel = "Add a caption"
        captionButton.accessibilityIdentifier = "camera.captionButton"
        captionButton.addTarget(self, action: #selector(captionTapped), for: .touchUpInside)
        embed(captionButton, in: captionBackdrop, cornerRadius: Self.glassDiameter / 2)
        captionBackdrop.isHidden = true
        captionBackdrop.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(captionStrip)
        captionStrip.addSubview(captionTextView)
        view.addSubview(captionBackdrop)

        // Position: centred on `captionCentre`, except while the keyboard is up,
        // when the strip rides just above it.
        let centre = captionStrip.centerYAnchor.constraint(equalTo: view.topAnchor)
        captionCentreConstraint = centre
        centre.isActive = true
        captionBottomConstraint = captionStrip.bottomAnchor.constraint(
            equalTo: view.keyboardLayoutGuide.topAnchor, constant: -16
        )

        captionStrip.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(captionDragged(_:)))
        )
        // Tapping the photo types on it, the way a snap does.
        let tap = UITapGestureRecognizer(target: self, action: #selector(captionTapped))
        previewImageView.isUserInteractionEnabled = true
        previewImageView.addGestureRecognizer(tap)
    }

    private func layoutCaption() {
        captionCentreConstraint?.constant = view.bounds.height * captionCentre
    }

    @objc private func captionTapped() {
        guard !previewImageView.isHidden else { return }
        captionStrip.isHidden = false
        captionTextView.becomeFirstResponder()
    }

    @objc private func captionDragged(_ gesture: UIPanGestureRecognizer) {
        guard view.bounds.height > 0 else { return }
        let delta = gesture.translation(in: view).y / view.bounds.height
        gesture.setTranslation(.zero, in: view)
        let half = captionStrip.bounds.height / max(1, view.bounds.height) / 2
        captionCentre = min(max(captionCentre + delta, half), 1 - half)
        layoutCaption()
    }

    /// The caption as it will be stored and drawn, or nil when it is empty.
    private var caption: String? { Caption.normalize(captionTextView.text ?? "") }

    private func setMode(reviewing: Bool) {
        previewImageView.isHidden = !reviewing
        retakeBackdrop.isHidden = !reviewing
        usePhotoButton.isHidden = !reviewing
        shutterButton.isHidden = reviewing
        flipBackdrop.isHidden = reviewing
        captionBackdrop.isHidden = !reviewing
        previewLayer?.isHidden = reviewing
        if !reviewing {
            // Leaving review drops the caption with the shot it belonged to.
            captionTextView.resignFirstResponder()
            captionTextView.text = ""
            captionStrip.isHidden = true
            captionCentre = CaptionLayout.defaultCentre
            layoutCaption()
        }
    }

    private func showPermissionDenied() {
        shutterButton.isHidden = true
        flipBackdrop.isHidden = true

        let icon = UIImageView(
            image: UIImage(
                systemName: "camera.fill",
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 34, weight: .regular)
            )
        )
        icon.tintColor = Self.accent
        icon.contentMode = .center
        icon.isAccessibilityElement = false

        let title = UILabel()
        title.text = "Camera access is off"
        title.font = Self.roundedHeadline()
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .white
        title.textAlignment = .center
        title.numberOfLines = 0

        let label = UILabel()
        label.text = "PubDates only uses the camera to snap the beer in your hand — turn it on in Settings."
        label.textColor = UIColor(white: 1, alpha: 0.75)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true

        var settingsConfig = UIButton.Configuration.filled()
        settingsConfig.title = "Open Settings"
        settingsConfig.baseBackgroundColor = Self.accent
        settingsConfig.baseForegroundColor = Self.onAccent
        settingsConfig.cornerStyle = .capsule
        settingsConfig.contentInsets = NSDirectionalEdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
        settingsConfig.titleTextAttributesTransformer = Self.headlineTitle
        let settingsButton = UIButton(configuration: settingsConfig)
        settingsButton.accessibilityLabel = "Open Settings"
        settingsButton.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)
        settingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true

        let stack = UIStackView(arrangedSubviews: [icon, title, label, settingsButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .center
        stack.setCustomSpacing(20, after: label)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
        ])
    }

    /// SF Rounded, bold, at the Title 3 reading size — the display face from the
    /// design direction, still following Dynamic Type.
    private static func roundedHeadline() -> UIFont {
        let base = UIFont.preferredFont(forTextStyle: .title3)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded)?
            .withSymbolicTraits(.traitBold) else { return base }
        return UIFont(descriptor: descriptor, size: 0)
    }

    // MARK: Camera

    private func startCamera() {
        if previewLayer == nil {
            let layer = AVCaptureVideoPreviewLayer(session: camera.session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.insertSublayer(layer, at: 0)
            previewLayer = layer
        }
        shutterHaptic.prepare()
        camera.start(position: position)
    }

    // MARK: Actions

    @objc private func cancelTapped() {
        onCancel?()
    }

    @objc private func flipTapped() {
        position = position == .back ? .front : .back
        camera.setPosition(position)
    }

    @objc private func shutterTapped() {
        shutterHaptic.impactOccurred()
        shutterButton.isEnabled = false
        let delegate = PhotoCaptureDelegate { [weak self] data in
            self?.handleCaptureResult(data)
        }
        pendingDelegate = delegate
        camera.capturePhoto(delegate: delegate)
    }

    @objc private func shutterPressed() {
        UIView.animate(withDuration: 0.12, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.shutterCore.transform = CGAffineTransform(scaleX: 0.88, y: 0.88)
            self.shutterCore.alpha = 0.8
        }
    }

    @objc private func shutterReleased() {
        UIView.animate(withDuration: 0.16, delay: 0, options: [.beginFromCurrentState, .curveEaseOut]) {
            self.shutterCore.transform = .identity
            self.shutterCore.alpha = 1
        }
    }

    @objc private func retakeTapped() {
        capturedImage = nil
        previewImageView.image = nil
        setMode(reviewing: false)
        camera.start(position: position)
    }

    @objc private func usePhotoTapped() {
        captionTextView.resignFirstResponder()
        guard let image = capturedImage,
              let jpeg = Self.downscaledJPEG(image, caption: caption, centre: captionCentre)
        else {
            retakeTapped() // corrupt capture — fall back to live view
            return
        }
        onUsePhoto?(jpeg, caption)
    }

    @objc private func openSettingsTapped() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func handleCaptureResult(_ data: Data?) {
        pendingDelegate = nil
        shutterButton.isEnabled = true
        shutterReleased()
        guard let data, let image = UIImage(data: data) else {
            return // capture failed — stay on the live view for another try
        }
        capturedImage = image
        camera.stop() // freeze while reviewing; retake restarts
        previewImageView.image = image
        setMode(reviewing: true)
    }

    /// Max 1080px long edge, JPEG quality 0.8 — comfortably under the 5 MB
    /// storage-rules cap while staying crisp on a phone screen. The caption is
    /// drawn into the pixels here, so it travels with the photo: view-once, the
    /// screenshot shield and the expiry all keep working untouched, and nothing
    /// new has to be served alongside it.
    private static func downscaledJPEG(
        _ image: UIImage, caption: String? = nil,
        centre: CGFloat = CaptionLayout.defaultCentre,
        maxLongEdge: CGFloat = 1080, quality: CGFloat = 0.8
    ) -> Data? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let longEdge = max(pixelWidth, pixelHeight)
        guard longEdge > 0 else { return nil }
        let scale = min(1, maxLongEdge / longEdge)
        let targetSize = CGSize(width: (pixelWidth * scale).rounded(.down),
                                height: (pixelHeight * scale).rounded(.down))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // render in pixels, not points
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
            guard let caption else { return }
            draw(caption: caption, centre: centre, in: targetSize, context: context.cgContext)
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// The same band the review screen shows, at the photo's own scale: one
    /// `CaptionLayout` decides both, so what you typed on is what gets uploaded.
    private static func draw(caption: String, centre: CGFloat, in size: CGSize, context: CGContext) {
        let lines = caption.components(separatedBy: "\n").count
        let layout = CaptionLayout(lineCount: lines, centre: centre)
        let strip = layout.stripRect(in: size)
        context.setFillColor(UIColor.black.withAlphaComponent(CaptionLayout.stripOpacity).cgColor)
        context.fill(strip)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: layout.fontSize(in: size), weight: .semibold),
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph,
        ]
        let inset = layout.horizontalInset(in: size)
        let textBox = strip.insetBy(dx: inset, dy: 0)
        let attributed = NSAttributedString(string: caption, attributes: attributes)
        let height = attributed.boundingRect(
            with: CGSize(width: textBox.width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil
        ).height
        attributed.draw(in: CGRect(x: textBox.minX, y: strip.midY - height / 2,
                                   width: textBox.width, height: height))
    }
}

// MARK: - Caption editing

extension CameraCaptureViewController: UITextViewDelegate {
    func textViewDidBeginEditing(_ textView: UITextView) {
        // The strip rides above the keyboard while you type, then goes back to
        // wherever you had dragged it.
        captionCentreConstraint?.isActive = false
        captionBottomConstraint?.isActive = true
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            textView.resignFirstResponder()
            return false
        }
        let current = textView.text ?? ""
        guard let r = Range(range, in: current) else { return true }
        let proposed = current.replacingCharacters(in: r, with: text)
        return proposed == Caption.clampWhileTyping(proposed)
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        captionBottomConstraint?.isActive = false
        captionCentreConstraint?.isActive = true
        layoutCaption()
        // No text, no strip.
        captionStrip.isHidden = Caption.normalize(textView.text ?? "") == nil
        UIView.animate(withDuration: 0.2) { self.view.layoutIfNeeded() }
    }
}

// MARK: - Session controller

/// Owns the `AVCaptureSession` and serializes ALL session work onto one
/// dispatch queue — AVFoundation types aren't Sendable, so this is the seam
/// that keeps Swift 6 strict concurrency happy (`@unchecked Sendable`: every
/// touch of `session`/`photoOutput` happens on `queue`).
final class CameraSessionController: @unchecked Sendable {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.timjansen.beerwithme.camera-session")

    func start(position: AVCaptureDevice.Position) {
        queue.async {
            self.configure(position: position)
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func setPosition(_ position: AVCaptureDevice.Position) {
        queue.async {
            self.configure(position: position)
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func capturePhoto(delegate: PhotoCaptureDelegate) {
        queue.async {
            // No input (permission revoked mid-session, simulator, device failure):
            // AVCapturePhotoOutput raises an ObjC exception instead of erroring.
            guard let connection = self.photoOutput.connection(with: .video), connection.isActive else {
                delegate.fail()
                return
            }
            // The preview layer mirrors the front camera on its own; the photo
            // output does not, so a selfie came out flipped against what the
            // screen showed (Tim, 2026-09-11: "de foto is gespiegeld"). Match
            // the preview: mirror the capture for the front camera only.
            let isFront = (self.session.inputs.first as? AVCaptureDeviceInput)?.device.position == .front
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = isFront
            }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            self.photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func configure(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        session.inputs.forEach(session.removeInput)
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }
}

// MARK: - Capture delegate

/// One-shot delegate, retained by the view controller for the duration of a
/// capture. AVFoundation calls back on its own internal queue, hence the hop
/// to the MainActor-isolated completion.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @MainActor (Data?) -> Void

    init(completion: @escaping @MainActor (Data?) -> Void) {
        self.completion = completion
    }

    /// Capture could not even start (no active video connection).
    func fail() {
        let completion = completion
        Task { @MainActor in
            completion(nil)
        }
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let completion = completion
        Task { @MainActor in
            completion(data)
        }
    }
}
