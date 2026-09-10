import AVFoundation
import BeerKit
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

// COMPILE-PARKED (Task 11): no Xcode on this machine — written against
// iOS 17 SDK APIs under Swift 6 concurrency, not yet compiled.

// MARK: - Deep link

/// The mate link, minted and parsed in one place so the QR code, the ShareLink
/// and the app shell can never drift. Two shapes are accepted:
///   https://beerwithme-prod.web.app/add/<username>   (universal link: opens the
///       app when installed, a web page with the TestFlight link otherwise)
///   pubdates://add/<username>                          (custom scheme, legacy QR)
enum MateLink {
    static let scheme = "pubdates"
    static let host = "add"
    static let webHost = "beerwithme-prod.web.app"

    /// The text encoded in the QR and shared by the ShareLink.
    static func link(for username: String) -> String {
        "https://\(webHost)/\(host)/\(username)"
    }

    /// The username in a mate link, normalized — or nil for anything else.
    /// Deliberately strict: a scanned code is untrusted input.
    static func username(fromDeepLink url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" }
        switch url.scheme?.lowercased() {
        case scheme:
            guard url.host?.lowercased() == host, let first = components.first else { return nil }
            return Username.normalize(first)
        case "https":
            guard url.host?.lowercased() == webHost, components.count >= 2, components[0] == host else { return nil }
            return Username.normalize(components[1])
        default:
            return nil
        }
    }
}

extension Notification.Name {
    /// Posted by the app shell when a `pubdates://add/<username>` link opens the
    /// app; FriendsView observes it and runs the normal add-a-mate flow.
}

// MARK: - Sheet

/// Add a mate face to face: show your own code, or scan theirs. The scan hands
/// a normalized username back to FriendsView, which runs the same
/// search-and-send flow as typing it — no new service surface.
///
/// Design: docs/design/direction.md screen 5 — one accent, system controls,
/// grouped surfaces. The code itself stays black-on-white in both schemes
/// because that is what scanners expect.
struct QRMateView: View {
    let profile: UserProfile
    let onScanned: (String) -> Void

    private enum Mode: Hashable { case myCode, scan }
    private enum CameraState: Equatable { case idle, requesting, ready, denied, unavailable }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var mode: Mode = .myCode
    @State private var cameraState: CameraState = .idle
    @State private var qrImage: UIImage?
    /// One scan per sheet: the session stops on the first hit, this guards the
    /// callback against a metadata frame already in flight.
    @State private var hasHandledScan = false

    private var myLink: String { MateLink.link(for: profile.username) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Picker("Mode", selection: $mode) {
                    Text("My code").tag(Mode.myCode)
                    Text("Scan").tag(Mode.scan)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("QR mode")
                .accessibilityIdentifier("qr.scan")
                .padding(.horizontal, 20)
                .padding(.top, 8)

                switch mode {
                case .myCode: myCodePanel
                case .scan: scanPanel
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground.ignoresSafeArea())
            .navigationTitle("Add with QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("qr.done")
                }
            }
            .task(id: profile.username) {
                qrImage = Self.makeQRImage(for: MateLink.link(for: profile.username))
            }
            .task(id: mode) { await prepareCameraIfNeeded() }
            .onChange(of: scenePhase) { _, phase in
                // Coming back from Settings: the permission may have flipped.
                if phase == .active { Task { await prepareCameraIfNeeded() } }
            }
        }
    }

    // MARK: - My code

    private var myCodePanel: some View {
        ScrollView {
            VStack(spacing: 16) {
                AvatarView(name: profile.displayName, size: 56)
                Text("@\(profile.username)")
                    .font(Theme.displayTitle2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("Your username, @\(profile.username)")

                qrSurface

                Text("Let a mate scan this to add you.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                ShareLink(item: myLink) {
                    Label("Share your link", systemImage: "square.and.arrow.up")
                        .frame(minHeight: 44)
                }
                .buttonStyle(PillButtonStyle(emphasis: .tinted))
                .accessibilityLabel("Share your add link")
                .accessibilityIdentifier("qr.share")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// A white plate under the code: scanners want black on white, and that must
    /// hold in dark mode too, so this surface is literal white, not semantic.
    private var qrSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous)
                .fill(Color.white)
            if let qrImage {
                Image(uiImage: qrImage)
                    .resizable()
                    .interpolation(.none)   // crisp module edges, never blurred
                    .frame(width: 240, height: 240)
                    .accessibilityAddTraits(.isImage)
                    .accessibilityLabel("QR code for @\(profile.username)")
                    .accessibilityIdentifier("qr.mycode")
            } else {
                ProgressView()
                    .frame(width: 240, height: 240)
            }
        }
        .frame(width: 280, height: 280)
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
    }

    /// CoreImage QR at correction level M, scaled 10× before rasterizing so the
    /// modules land on whole pixels (`.interpolation(.none)` does the rest).
    private static func makeQRImage(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Scan

    @ViewBuilder
    private var scanPanel: some View {
        VStack(spacing: 14) {
            switch cameraState {
            case .idle, .requesting:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .ready:
                QRScannerView { username in handleScan(username) }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
                    .overlay { aimingFrame }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityElement()
                    .accessibilityLabel("Camera viewfinder")
                    .accessibilityHint("Point it at a mate's PubDates code to add them")
                    .accessibilityIdentifier("qr.viewfinder")
                Text("Point at a mate's code to add them.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            case .denied:
                notice(
                    title: "Camera access is off",
                    message: "PubDates only uses the camera to scan a mate's code — turn it on in Settings.",
                    showsSettings: true
                )
            case .unavailable:
                notice(
                    title: "No camera available",
                    message: "There's no camera to scan with here. Show your own code instead and let your mate scan it.",
                    showsSettings: false
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }

    private var aimingFrame: some View {
        RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(0.9), lineWidth: 3)
            .frame(width: 220, height: 220)
            .shadow(color: .black.opacity(0.35), radius: 6)
            .accessibilityHidden(true)
    }

    private func notice(title: String, message: String, showsSettings: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.accentInk)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.displayTitle2)
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if showsSettings {
                Button("Open Settings") { openSettings() }
                    .buttonStyle(PillButtonStyle(emphasis: .tinted))
                    .frame(minHeight: 44)
                    .accessibilityLabel("Open Settings")
                    .accessibilityIdentifier("qr.settings")
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    @MainActor
    private func prepareCameraIfNeeded() async {
        guard mode == .scan else { return }
        // Device discovery needs no permission, so "simulator / no camera" is
        // answered before we ever ask for access.
        guard AVCaptureDevice.default(for: .video) != nil else {
            cameraState = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraState = .ready
        case .notDetermined:
            cameraState = .requesting
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraState = granted ? .ready : .denied
        default: // .denied, .restricted
            cameraState = .denied
        }
    }

    @MainActor
    private func handleScan(_ username: String) {
        guard !hasHandledScan else { return }
        hasHandledScan = true
        Haptics.success()
        onScanned(username)
    }

    @MainActor
    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Scanner

/// Live viewfinder that reports the first PubDates mate link it sees.
struct QRScannerView: UIViewControllerRepresentable {
    let onFound: @MainActor (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        QRScannerViewController(onFound: onFound)
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

/// Hosts the preview layer and starts/stops the session with the view's life.
final class QRScannerViewController: UIViewController {
    private let scanner: QRScanSessionController
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(onFound: @escaping @MainActor (String) -> Void) {
        scanner = QRScanSessionController(onFound: onFound)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: scanner.session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        scanner.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        scanner.stop()
    }
}

/// Owns the `AVCaptureSession` and serializes ALL session work — configuration,
/// start/stop and the metadata callbacks — onto one queue. AVFoundation types
/// aren't Sendable, so this is the seam that keeps Swift 6 strict concurrency
/// happy (`@unchecked Sendable`: every touch of `session`/`metadataOutput`/
/// `hasFound` happens on `queue`).
final class QRScanSessionController: NSObject, AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    private let queue = DispatchQueue(label: "com.timjansen.beerwithme.qr-session")
    private let onFound: @MainActor (String) -> Void
    /// Queue-confined: the first match wins and the session stops.
    private var hasFound = false

    init(onFound: @escaping @MainActor (String) -> Void) {
        self.onFound = onFound
        super.init()
    }

    func start() {
        queue.async {
            self.configureIfNeeded()
            // No input (no camera, or access revoked): starting would spin a
            // session that can never deliver a frame.
            guard !self.session.inputs.isEmpty, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func configureIfNeeded() {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(metadataOutput)
        else { return }
        session.addInput(input)
        session.addOutput(metadataOutput)
        // Both only valid AFTER the output joins the session.
        metadataOutput.setMetadataObjectsDelegate(self, queue: queue)
        if metadataOutput.availableMetadataObjectTypes.contains(.qr) {
            metadataOutput.metadataObjectTypes = [.qr]
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasFound else { return }
        // Anything that isn't a PubDates mate link is skipped and the session
        // keeps scanning — no error state for a random poster QR.
        for object in metadataObjects {
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  code.type == .qr,
                  let payload = code.stringValue,
                  let url = URL(string: payload),
                  let username = MateLink.username(fromDeepLink: url)
            else { continue }
            hasFound = true
            if session.isRunning {
                session.stopRunning()
            }
            let onFound = self.onFound
            Task { @MainActor in
                onFound(username)
            }
            return
        }
    }
}
