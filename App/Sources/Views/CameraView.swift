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

final class CameraCaptureViewController: UIViewController {
    var onUsePhoto: ((Data) -> Void)?
    var onCancel: (() -> Void)?

    private let camera = CameraSessionController()
    private var position: AVCaptureDevice.Position = .back
    private var previewLayer: AVCaptureVideoPreviewLayer?
    /// Retains the in-flight capture delegate (AVCapturePhotoOutput doesn't).
    private var pendingDelegate: PhotoCaptureDelegate?
    private var capturedImage: UIImage?

    // Live controls
    private let shutterButton = UIButton(type: .custom)
    private let flipButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)
    // Review controls
    private let previewImageView = UIImageView()
    private let retakeButton = UIButton(type: .system)
    private let usePhotoButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
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
        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.image = UIImage(systemName: "xmark")
        cancelConfig.baseForegroundColor = .white
        cancelButton.configuration = cancelConfig
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        var flipConfig = UIButton.Configuration.plain()
        flipConfig.image = UIImage(systemName: "arrow.triangle.2.circlepath.camera")
        flipConfig.baseForegroundColor = .white
        flipButton.configuration = flipConfig
        flipButton.addTarget(self, action: #selector(flipTapped), for: .touchUpInside)

        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor(white: 1, alpha: 0.35).cgColor
        shutterButton.accessibilityLabel = "Take photo"
        shutterButton.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)

        previewImageView.contentMode = .scaleAspectFit
        previewImageView.backgroundColor = .black
        previewImageView.isHidden = true

        var retakeConfig = UIButton.Configuration.gray()
        retakeConfig.title = "Retake"
        retakeConfig.baseForegroundColor = .white
        retakeConfig.cornerStyle = .capsule
        retakeButton.configuration = retakeConfig
        retakeButton.isHidden = true
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)

        var useConfig = UIButton.Configuration.filled()
        useConfig.title = "Use Photo 🍺"
        useConfig.cornerStyle = .capsule
        usePhotoButton.configuration = useConfig
        usePhotoButton.isHidden = true
        usePhotoButton.addTarget(self, action: #selector(usePhotoTapped), for: .touchUpInside)

        for control in [previewImageView, cancelButton, flipButton, shutterButton, retakeButton, usePhotoButton] {
            control.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(control)
        }

        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: view.topAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            cancelButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            cancelButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),

            flipButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            flipButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -24),
            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),

            retakeButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 24),
            retakeButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -32),

            usePhotoButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -24),
            usePhotoButton.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -32),
        ])
    }

    private func setMode(reviewing: Bool) {
        previewImageView.isHidden = !reviewing
        retakeButton.isHidden = !reviewing
        usePhotoButton.isHidden = !reviewing
        shutterButton.isHidden = reviewing
        flipButton.isHidden = reviewing
        previewLayer?.isHidden = reviewing
    }

    private func showPermissionDenied() {
        shutterButton.isHidden = true
        flipButton.isHidden = true

        let label = UILabel()
        label.text = "Camera access is off.\nPints With Mates only uses the camera to snap the beer in your hand — turn it on in Settings."
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .body)

        var settingsConfig = UIButton.Configuration.filled()
        settingsConfig.title = "Open Settings"
        settingsConfig.cornerStyle = .capsule
        let settingsButton = UIButton(configuration: settingsConfig)
        settingsButton.addTarget(self, action: #selector(openSettingsTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [label, settingsButton])
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32),
        ])
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
        shutterButton.isEnabled = false
        let delegate = PhotoCaptureDelegate { [weak self] data in
            self?.handleCaptureResult(data)
        }
        pendingDelegate = delegate
        camera.capturePhoto(delegate: delegate)
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
