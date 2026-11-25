import AVFoundation
import CoreImage
import Foundation
import Observation
import CompactCore

/// Owns the capture session. Later tasks add outputs (mic, snaps, recording) via `queue`.
@MainActor @Observable
final class CameraController: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
                              AVCaptureVideoDataOutputSampleBufferDelegate {
    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private nonisolated let ciContext = CIContext()
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
    @ObservationIgnored nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "compact.video")
    /// Pending `captureFrame()` callers, resumed by the next video frame (lock-protected; video queue + main).
    @ObservationIgnored private let frameLock = NSLock()
    @ObservationIgnored nonisolated(unsafe) private var frameWaiters: [UUID: CheckedContinuation<CGImage?, Never>] = [:]
    /// Reasons the mic input must be present ("meter", later "vlog"). Mic is attached iff non-empty.
    @ObservationIgnored private var micRequired: Set<String> = []
    @ObservationIgnored nonisolated(unsafe) private var lastLevelTime: CFAbsoluteTime = 0  // audio queue only

    init(store: SettingsStore) {
        self.store = store
        super.init()
        refresh()
    }

    /// Re-reads the device lists (no permission needed) so Settings pickers are current.
    func refreshDevices() {
        refresh()
        microphones = Self.discoverMicrophones()
    }

    // MARK: - Microphone

    func setMicMeter(enabled: Bool) {
        micMeterOn = enabled
        store.update { $0.showMicMeter = enabled }
        if enabled { requireMic("meter") } else { releaseMic("meter") }
    }

    func selectMicrophone(id: String) {
        store.update { $0.microphoneID = id }
        // Frozen while recording: swapping the input would break the movie output's audio.
        if !micRequired.isEmpty, !micRequired.contains("vlog") { applyMic() }
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
        if micRequired.isEmpty { audioLevel = 0 }
        applyMic()
    }

    /// True while any reason (meter, vlog) needs the mic. Late level updates are dropped once false.
    private var micIsWanted: Bool { !micRequired.isEmpty }

    /// Reconciles the mic input and the meter's data output with `micRequired`.
    /// The audio input is never removed/re-added when the wanted device is already attached: that would
    /// break a running movie output's audio connection. Meter on/off only adds/removes the data output.
    private func applyMic() {
        microphones = Self.discoverMicrophones()
        let want = !micRequired.isEmpty && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let device = want ? preferredMicrophone() : nil
        let meter = device != nil && micRequired.contains("meter")
        let session = session, output = audioOutput
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            let current = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                .first { $0.device.hasMediaType(.audio) }
            var attached = current != nil
            if current?.device.uniqueID != device?.uniqueID {
                if let current { session.removeInput(current); attached = false }
                if let device, let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) {
                    session.addInput(input)
                    attached = true
                }
            }
            let hasOutput = session.outputs.contains(output)
            if meter, attached, !hasOutput, session.canAddOutput(output) {
                output.setSampleBufferDelegate(self, queue: self.audioQueue)
                session.addOutput(output)
            } else if (!meter || !attached), hasOutput {
                session.removeOutput(output)
            }
            session.commitConfiguration()
            if !meter { Task { @MainActor in if !self.micIsWanted { self.audioLevel = 0 } } }
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
        if output === videoOutput { handleVideoFrame(sampleBuffer); return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLevelTime >= 0.05 else { return }   // <= 20 updates/s
        lastLevelTime = now
        let channels = connection.audioChannels
        guard !channels.isEmpty else { return }
        let avg = channels.map(\.averagePowerLevel).reduce(0, +) / Float(channels.count)
        let level = normalizedLevel(decibels: avg)
        Task { @MainActor [weak self] in
            // Drop late updates that arrive after the meter/mic was turned off.
            guard let self, self.micIsWanted else { return }
            self.audioLevel = level
        }
    }

    // MARK: - Snaps

    /// Returns the next video frame, unmirrored, or nil if none arrives within 2 seconds.
    func captureFrame() async -> CGImage? {
        let id = UUID()
        return await withCheckedContinuation { (cont: CheckedContinuation<CGImage?, Never>) in
            frameLock.lock()
            frameWaiters[id] = cont
            frameLock.unlock()
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.resumeWaiter(id, with: nil)
            }
        }
    }

    private nonisolated func resumeWaiter(_ id: UUID, with image: CGImage?) {
        frameLock.lock()
        let cont = frameWaiters.removeValue(forKey: id)
        frameLock.unlock()
        cont?.resume(returning: image)
    }

    private nonisolated func handleVideoFrame(_ sampleBuffer: CMSampleBuffer) {
        frameLock.lock()
        let ids = Array(frameWaiters.keys)
        frameLock.unlock()
        guard !ids.isEmpty, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ci = CIImage(cvPixelBuffer: pixels)
        let image = ciContext.createCGImage(ci, from: ci.extent)
        for id in ids { resumeWaiter(id, with: image) }
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

    // MARK: - Movie output (vlog)

    /// Adds `output` to the running session on the session queue and turns mirroring off on its video
    /// connection. Returns a failure message if the session refuses it; the snap output is left untouched.
    func attachMovieOutput(_ output: AVCaptureMovieFileOutput) async -> String? {
        let session = session
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            queue.async {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                guard session.canAddOutput(output) else {
                    cont.resume(returning: "This Mac's camera can't record video while snaps are enabled.")
                    return
                }
                session.addOutput(output)
                if let conn = output.connection(with: .video) {
                    conn.automaticallyAdjustsVideoMirroring = false
                    if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
                }
                cont.resume(returning: nil)
            }
        }
    }

    /// Removes the movie output so an idle session stays light.
    func detachMovieOutput(_ output: AVCaptureMovieFileOutput) {
        let session = session
        queue.async {
            session.beginConfiguration()
            if session.outputs.contains(output) { session.removeOutput(output) }
            session.commitConfiguration()
        }
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
            if let self {
                let output = self.videoOutput
                if !session.outputs.contains(output), session.canAddOutput(output) {
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.videoQueue)
                    session.addOutput(output)
                }
                if let conn = output.connection(with: .video) {
                    // Snaps are true-to-life: never mirrored (the preview mirrors in the view layer).
                    conn.automaticallyAdjustsVideoMirroring = false
                    if conn.isVideoMirroringSupported { conn.isVideoMirrored = false }
                }
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
