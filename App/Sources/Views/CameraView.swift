import AVFoundation
import SwiftUI
import UIKit

// COMPILE-PARKED (Task 10): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

/// Live camera capture — the ONLY photo source (no photo-library access, by
/// design: beer photos are taken in the moment). Back camera by default with a
/// flip button; shutter → retake / use-photo review. Returns a JPEG downscaled
/// to ≤ 1080px on the long edge at 0.8 quality via `onCapture`, then dismisses.
struct CameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> CameraCaptureViewController {
        let controller = CameraCaptureViewController()
        let onCapture = self.onCapture
        let dismiss = self.dismiss
        controller.onUsePhoto = { data in
            onCapture(data)
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
    var onUsePhoto: ((Data) -> Void)?
    var onCancel: (() -> Void)?

    private let camera = CameraSessionController()
    private var position: AVCaptureDevice.Position = .back
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Retains the in-flight capture delegate (AVCapturePhotoOutput doesn't).
    private var pendingDelegate: PhotoCaptureDelegate?
    private var capturedImage: UIImage?
    private let shutterHaptic = UIImpactFeedbackGenerator(style: .medium)

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

        previewImageView.contentMode = .scaleAspectFit
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

    private func setMode(reviewing: Bool) {
        previewImageView.isHidden = !reviewing
        retakeBackdrop.isHidden = !reviewing
        usePhotoButton.isHidden = !reviewing
        shutterButton.isHidden = reviewing
        flipBackdrop.isHidden = reviewing
        previewLayer?.isHidden = reviewing
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
        guard let image = capturedImage, let jpeg = Self.downscaledJPEG(image) else {
            retakeTapped() // corrupt capture — fall back to live view
            return
        }
        onUsePhoto?(jpeg)
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
    /// storage-rules cap while staying crisp on a phone screen.
    private static func downscaledJPEG(
        _ image: UIImage, maxLongEdge: CGFloat = 1080, quality: CGFloat = 0.8
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
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
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
