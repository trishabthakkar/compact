import AVFoundation
import Observation
import CompactCore

/// Owns the capture session. Later tasks add outputs (mic, snaps, recording) via `queue`.
@MainActor @Observable
final class CameraController {
    @ObservationIgnored let session = AVCaptureSession()
    private(set) var access: CameraAccess = .notDetermined
    private(set) var cameras: [AVCaptureDevice] = []

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let queue = DispatchQueue(label: "compact.camera")
    @ObservationIgnored private var wantsRunning = false

    init(store: SettingsStore) {
        self.store = store
        refresh()
    }

    func start() {
        wantsRunning = true
        refresh()
        if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.refresh()
                    if self.wantsRunning { self.startIfAllowed() }
                }
            }
            return
        }
        startIfAllowed()
    }

    func stop() {
        wantsRunning = false
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }

    func selectCamera(id: String) {
        store.update { $0.cameraID = id }
        guard let device = cameras.first(where: { $0.uniqueID == id }) else { return }
        configure(with: device)
    }

    // MARK: - Private

    private func refresh() {
        cameras = Self.discoverCameras()
        access = .from(status: AVCaptureDevice.authorizationStatus(for: .video),
                       hasDevice: !cameras.isEmpty)
    }

    private func startIfAllowed() {
        guard access == .allowed, let device = preferredDevice() else { return }
        configure(with: device)
    }

    private func preferredDevice() -> AVCaptureDevice? {
        if let id = store.settings.cameraID, let d = cameras.first(where: { $0.uniqueID == id }) {
            return d
        }
        return AVCaptureDevice.default(for: .video) ?? cameras.first
    }

    private func configure(with device: AVCaptureDevice) {
        let session = session
        let shouldRun = wantsRunning
        queue.async {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
            session.commitConfiguration()
            if shouldRun, !session.isRunning { session.startRunning() }
        }
    }

    private static func discoverCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}
