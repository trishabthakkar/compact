import AVFoundation
import Foundation
import Observation
import CompactCore

/// Owns the capture session. Later tasks add outputs (mic, snaps, recording) via `queue`.
@MainActor @Observable
final class CameraController: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    @ObservationIgnored let session = AVCaptureSession()
    private(set) var access: CameraAccess = .notDetermined
    private(set) var cameras: [AVCaptureDevice] = []
    private(set) var microphones: [AVCaptureDevice] = []
    /// 0...1, updated at most 20 times per second.
    private(set) var audioLevel: Double = 0
    private(set) var micDenied = false
    private(set) var micMeterOn = false

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let queue = DispatchQueue(label: "compact.camera")
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private let audioOutput = AVCaptureAudioDataOutput()
    @ObservationIgnored private let audioQueue = DispatchQueue(label: "compact.audio")
    /// Reasons the mic input must be present ("meter", later "vlog"). Mic is attached iff non-empty.
    @ObservationIgnored private var micRequired: Set<String> = []
    @ObservationIgnored nonisolated(unsafe) private var lastLevelTime: CFAbsoluteTime = 0  // audio queue only

    init(store: SettingsStore) {
        self.store = store
        super.init()
        refresh()
    }

    // MARK: - Microphone

    func setMicMeter(enabled: Bool) {
        micMeterOn = enabled
        store.update { $0.showMicMeter = enabled }
        if enabled { requireMic("meter") } else { releaseMic("meter") }
    }

    func selectMicrophone(id: String) {
        store.update { $0.microphoneID = id }
        if !micRequired.isEmpty { applyMic() }
    }

    /// Keeps the mic input attached for `reason` (e.g. "vlog") until released.
    func requireMic(_ reason: String) {
        micRequired.insert(reason)
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else {
            micDenied = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            applyMic()
            return
        }
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.micDenied = AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
                self.applyMic()
            }
        }
    }

    func releaseMic(_ reason: String) {
        micRequired.remove(reason)
        applyMic()
    }

    private func applyMic() {
        microphones = Self.discoverMicrophones()
        let want = !micRequired.isEmpty && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let device = want ? preferredMicrophone() : nil
        let session = session, output = audioOutput
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            for input in session.inputs where (input as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true {
                session.removeInput(input)
            }
            if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
                if !session.outputs.contains(output), session.canAddOutput(output) {
                    output.setSampleBufferDelegate(self, queue: self.audioQueue)
                    session.addOutput(output)
                }
            } else if session.outputs.contains(output) {
                session.removeOutput(output)
            }
            session.commitConfiguration()
            if device == nil { Task { @MainActor in self.audioLevel = 0 } }
        }
    }

    private func preferredMicrophone() -> AVCaptureDevice? {
        if let id = store.settings.microphoneID, let d = microphones.first(where: { $0.uniqueID == id }) {
            return d
        }
        return AVCaptureDevice.default(for: .audio) ?? microphones.first
    }

    nonisolated func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelTime >= 0.05 else { return }   // <= 20 updates/s
        lastLevelTime = now
        let channels = connection.audioChannels
        guard !channels.isEmpty else { return }
        let avg = channels.map(\.averagePowerLevel).reduce(0, +) / Float(channels.count)
        let level = normalizedLevel(decibels: avg)
        Task { @MainActor [weak self] in self?.audioLevel = level }
    }

    func start() {
        wantsRunning = true
        refresh()
        if store.settings.showMicMeter, !micMeterOn { setMicMeter(enabled: true) }
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
        queue.async { [weak self] in
            session.beginConfiguration()
            for input in session.inputs where (input as? AVCaptureDeviceInput)?.device.hasMediaType(.video) == true {
                session.removeInput(input)
            }
            var added = false
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                session.addInput(input)
                added = true
            }
            if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
            session.commitConfiguration()
            if !added {
                Task { @MainActor in self?.access = .noCamera }
                return
            }
            if shouldRun, !session.isRunning { session.startRunning() }
        }
    }

    private static func discoverMicrophones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    private static func discoverCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
}
