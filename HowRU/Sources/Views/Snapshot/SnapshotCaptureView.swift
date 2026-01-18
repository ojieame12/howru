import SwiftUI
import AVFoundation

/// Camera view for capturing selfie snapshots
struct SnapshotCaptureView: View {
    let onCapture: (Data) -> Void
    let onCancel: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var camera = CameraController()
    @State private var flashEnabled = false
    @State private var isCapturing = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                Color.black.ignoresSafeArea()

                if camera.isAuthorized {
                    CameraPreview(session: camera.session)
                        .ignoresSafeArea()
                } else if camera.authorizationDenied {
                    permissionDeniedView
                } else {
                    // Requesting permission
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }

                // UI Overlay
                VStack {
                    // Top bar
                    HStack {
                        Button(action: {
                            HowRUHaptics.light()
                            onCancel()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }

                        Spacer()

                        // Flash toggle
                        if camera.hasFlash {
                            Button(action: {
                                HowRUHaptics.light()
                                flashEnabled.toggle()
                            }) {
                                Image(systemName: flashEnabled ? "bolt.fill" : "bolt.slash.fill")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(flashEnabled ? .yellow : .white)
                                    .frame(width: 44, height: 44)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, HowRUSpacing.screenEdge)
                    .padding(.top, HowRUSpacing.md)

                    Spacer()

                    // Instructions
                    Text("Take a quick selfie for your circle")
                        .font(HowRUFont.body())
                        .foregroundColor(.white)
                        .padding(.horizontal, HowRUSpacing.lg)
                        .padding(.vertical, HowRUSpacing.sm)
                        .background(Color.black.opacity(0.4))
                        .clipShape(Capsule())

                    Spacer()

                    // Bottom controls
                    HStack {
                        // Camera flip button
                        Button(action: {
                            HowRUHaptics.light()
                            camera.switchCamera()
                        }) {
                            Image(systemName: "camera.rotate")
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }

                        Spacer()

                        // Capture button
                        Button(action: capturePhoto) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 72, height: 72)

                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 60, height: 60)
                                    .scaleEffect(isCapturing ? 0.9 : 1.0)
                            }
                        }
                        .disabled(isCapturing || !camera.isReady)

                        Spacer()

                        // Placeholder for symmetry
                        Color.clear
                            .frame(width: 56, height: 56)
                    }
                    .padding(.horizontal, HowRUSpacing.xl)
                    .padding(.bottom, HowRUSpacing.xxl)
                }
            }
        }
        .onAppear {
            camera.checkAuthorization()
        }
        .onDisappear {
            camera.stop()
        }
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        VStack(spacing: HowRUSpacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48, weight: .medium))
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: HowRUSpacing.sm) {
                Text("Camera Access Required")
                    .font(HowRUFont.headline2())
                    .foregroundColor(.white)

                Text("Allow camera access in Settings to add snapshots to your check-ins.")
                    .font(HowRUFont.body())
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, HowRUSpacing.xl)
            }

            Button(action: openSettings) {
                Text("Open Settings")
            }
            .buttonStyle(HowRUPrimaryButtonStyle())
            .padding(.horizontal, HowRUSpacing.xl)
        }
    }

    // MARK: - Actions

    private func capturePhoto() {
        guard camera.isReady else { return }

        isCapturing = true
        HowRUHaptics.medium()

        withAnimation(.howruSnappy) {
            // Visual feedback
        }

        camera.capturePhoto(withFlash: flashEnabled) { data in
            DispatchQueue.main.async {
                isCapturing = false
                if let imageData = data {
                    HowRUHaptics.success()
                    onCapture(imageData)
                } else {
                    HowRUHaptics.error()
                }
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Camera Controller

/// Camera controller that manages AVCaptureSession on a dedicated queue
/// All published properties are updated on the main thread
final class CameraController: NSObject, ObservableObject, @unchecked Sendable {
    @Published var isAuthorized = false
    @Published var authorizationDenied = false
    @Published var isReady = false
    @Published var hasFlash = false

    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var currentDevice: AVCaptureDevice?
    private var captureCompletion: ((Data?) -> Void)?
    private var isUsingFrontCamera = true
    private let sessionQueue = DispatchQueue(label: "com.howru.camera.session")

    func checkAuthorization() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isAuthorized = granted
                    self?.authorizationDenied = !granted
                    if granted {
                        self?.setupCamera()
                    }
                }
            }
        case .denied, .restricted:
            DispatchQueue.main.async {
                self.authorizationDenied = true
            }
        @unknown default:
            DispatchQueue.main.async {
                self.authorizationDenied = true
            }
        }
    }

    private func setupCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            // Add front camera
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.currentDevice = device
                        let deviceHasFlash = device.hasFlash
                        DispatchQueue.main.async {
                            self.hasFlash = deviceHasFlash
                        }
                    }
                } catch {
                    print("Failed to add camera input: \(error)")
                }
            }

            // Add photo output
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }

            self.session.commitConfiguration()

            // Start session
            self.session.startRunning()

            DispatchQueue.main.async {
                self.isReady = true
            }
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let currentInput = self.session.inputs.first as? AVCaptureDeviceInput else { return }

            self.session.beginConfiguration()
            self.session.removeInput(currentInput)

            let newPosition: AVCaptureDevice.Position = self.isUsingFrontCamera ? .back : .front
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if self.session.canAddInput(input) {
                        self.session.addInput(input)
                        self.currentDevice = device
                        self.isUsingFrontCamera = !self.isUsingFrontCamera
                        let deviceHasFlash = device.hasFlash
                        DispatchQueue.main.async {
                            self.hasFlash = deviceHasFlash
                        }
                    }
                } catch {
                    // Restore original
                    if self.session.canAddInput(currentInput) {
                        self.session.addInput(currentInput)
                    }
                }
            }

            self.session.commitConfiguration()
        }
    }

    func capturePhoto(withFlash: Bool, completion: @escaping (Data?) -> Void) {
        captureCompletion = completion

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let settings = AVCapturePhotoSettings()
            if let device = self.currentDevice, device.hasFlash {
                settings.flashMode = withFlash ? .on : .off
            }

            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = photo.fileDataRepresentation()
        DispatchQueue.main.async { [weak self] in
            self?.captureCompletion?(data)
        }
    }
}

// MARK: - Camera Preview

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        context.coordinator.previewLayer = previewLayer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Preview

#Preview("Snapshot Capture") {
    SnapshotCaptureView(
        onCapture: { _ in print("Captured") },
        onCancel: { print("Cancelled") }
    )
}
