#if os(iOS)
import AVFoundation
import SwiftUI

/// Scans the QR code printed by `opencode pair`.
///
/// The scanner is iOS-only: visionOS and the Watch have no camera to scan
/// with, so they keep the paste-a-link path.
@available(iOS 17.0, *)
struct QRScannerView: View {
    /// The scanned payload, handed back to the caller.
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cameraState: CameraState = .idle

    private enum CameraState {
        case idle
        case running
        case denied
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                scannerPreview
                overlay
            }
            .navigationTitle(L10n.t(.hostScanTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t(.commonCancel)) { dismiss() }
                }
            }
            .task { await start() }
            .onDisappear { stop() }
        }
    }

    @ViewBuilder
    private var scannerPreview: some View {
        switch cameraState {
        case .idle, .running:
            QRScannerRepresentable(onScan: onScan)
                .ignoresSafeArea()
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.largeTitle)
                Text(L10n.t(.hostPairCameraDenied))
                    .multilineTextAlignment(.center)
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link(L10n.t(.settingsOpenSystem), destination: settings)
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(.white)
            .padding()
        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                Text(message)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding()
        }
    }

    @ViewBuilder
    private var overlay: some View {
        VStack {
            Spacer()
            Text(L10n.t(.hostPairCameraHint))
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    private func start() async {
        guard case .idle = cameraState else { return }
        guard AVCaptureDevice.default(for: .video) != nil else {
            // The simulator has no camera: say so instead of showing a black
            // rectangle.
            cameraState = .failed(L10n.t(.hostPairCameraUnavailable))
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraState = .running
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraState = granted ? .running : .denied
        default:
            cameraState = .denied
        }
    }

    private func stop() {
        QRScannerRepresentable.stopSession()
    }
}

/// The camera preview and the QR metadata output.
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    static var session: AVCaptureSession?

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerController, context: Context) {}

    static func stopSession() {
        session?.stopRunning()
        session = nil
    }
}

@available(iOS 17.0, *)
private final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            return
        }
        captureSession.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard captureSession.canAddOutput(output) else { return }
        captureSession.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer

        QRScannerRepresentable.session = captureSession
        DispatchQueue.global(qos: .userInitiated).async { [captureSession] in
            captureSession.startRunning()
        }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let payload = object.stringValue else {
            return
        }
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
        onScan?(payload)
    }
}

#endif // os(iOS)
