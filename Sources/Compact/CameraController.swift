import AppKit
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
    /// Whether a microphone is actually connected to the session (false → a vlog would have no sound).
    private(set) var micAttached = false
    /// True while the mic is being connected, so the "no sound" icon doesn't flicker at the start.
    private(set) var micSettingUp = false
    /// Set when the camera stopped working (unplugged, error); cleared once it's running again.
    @ObservationIgnored private var sessionLost = false
    @ObservationIgnored private var recoveryAttempts = 0

    /// Called when the user allowed camera access from the system prompt after the panel that triggered the
    /// request was already closed by the dialog; the owner should reopen the panel.
    @ObservationIgnored var onAccessGrantedAfterPanelClosed: (() -> Void)?

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
        observeCameraChanges()
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

    /// Resolves microphone authorization, showing the system prompt first if it was never asked.
    /// Returns true when the mic may be used. Always awaited before a vlog starts so audio is wired in from frame one.
    func ensureMicAccess() async -> Bool {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
        let ok = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        micDenied = !ok
        return ok
    }

    /// Keeps the mic input attached for `reason` (e.g. "vlog") until released.
    func requireMic(_ reason: String) {
        micRequired.insert(reason)
        micSettingUp = true
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
        let preferred = want ? preferredMicrophone() : nil
        // While recording, keep whatever mic is already attached; re-resolving could swap it mid-file.
        let keepCurrent = want && micRequired.contains("vlog")
        let wantsMeter = micRequired.contains("meter")
        let session = session, output = audioOutput
        queue.async { [weak self] in
            guard let self else { return }
            session.beginConfiguration()
            let current = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                .first { $0.device.hasMediaType(.audio) }
            let device = keepCurrent ? (current?.device ?? preferred) : preferred
            let meter = device != nil && wantsMeter
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
            let micIsIn = attached
            Task { @MainActor in self.micAttached = micIsIn; self.micSettingUp = false }
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
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    self.refresh()
                    if self.wantsRunning {
                        self.startIfAllowed()
                    } else if granted {
                        // The system dialog closed the transient popover (stop() ran): reopen it.
                        self.onAccessGrantedAfterPanelClosed?()
                    }
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
        // Frozen while recording: swapping the video input would break the movie output.
        guard !micRequired.contains("vlog") else { return }
        store.update { $0.cameraID = id }
        guard let device = cameras.first(where: { $0.uniqueID == id }) else { return }
        configure(with: device)
    }

    // MARK: - Movie output (vlog)

    /// Adds `output` to the running session on the session queue and turns mirroring off on its video
    /// connection. Returns a failure message if the session refuses it; the snap output is left untouched.
    func attachMovieOutput(_ output: AVCaptureMovieFileOutput) async -> String? {
        let session = session
        // Match what you see: the video is mirrored whenever the live preview is mirrored.
        let mirror = store.settings.mirrorPreview
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            queue.async {
                session.beginConfiguration()
                defer { session.commitConfiguration() }
                guard session.canAddOutput(output) else {
                    cont.resume(returning: "Compact couldn't start recording on this camera. Try closing other apps that use the camera and record again.")
                    return
                }
                session.addOutput(output)
                if let conn = output.connection(with: .video) {
                    conn.automaticallyAdjustsVideoMirroring = false
                    if conn.isVideoMirroringSupported { conn.isVideoMirrored = mirror }
                }
                cont.resume(returning: nil)
            }
        }
    }

    /// Starts recording on the session queue once the output has an active, enabled connection.
    /// Connections can take a moment to come up after the output is added; calling
    /// `startRecording` before then throws "No active/enabled connections". Returns false if
    /// no connection became ready within 3 seconds (recording was not started).
    func startMovieRecording(_ output: AVCaptureMovieFileOutput, to url: URL,
                             delegate: AVCaptureFileOutputRecordingDelegate) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            queue.async {
                let ready = { output.connections.contains { $0.isActive && $0.isEnabled } }
                let deadline = Date().addingTimeInterval(3)
                while !ready() && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
                guard ready() else { cont.resume(returning: false); return }
                output.startRecording(to: url, recordingDelegate: delegate)
                cont.resume(returning: true)
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

    // MARK: - Camera problems

    /// Notices a camera being unplugged, taken by another app or failing, and permission being
    /// changed in System Settings, so the panel shows a message and recovers on its own.
    private func observeCameraChanges() {
        let center = NotificationCenter.default
        let recover: [Notification.Name] = [AVCaptureDevice.wasConnectedNotification,
                                           AVCaptureDevice.wasDisconnectedNotification,
                                           NSApplication.didBecomeActiveNotification]
        for name in recover {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recoverIfNeeded() }
            }
        }
        center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.cameraLost() }
        }
    }

    /// Restarts the camera if it should be running but isn't (or its device went away). Never
    /// touches the session during a recording, since that would break the video file; the owner
    /// calls this again once a recording ends.
    func recoverIfNeeded() {
        refresh()
        guard wantsRunning, !micRequired.contains("vlog"),
              AVCaptureDevice.authorizationStatus(for: .video) == .authorized,
              let device = preferredDevice() else { return }
        let session = session, lost = sessionLost
        queue.async { [weak self] in
            let healthy = session.isRunning && session.inputs.contains {
                guard let input = $0 as? AVCaptureDeviceInput else { return false }
                return input.device.hasMediaType(.video) && input.device.isConnected
            }
            if healthy && !lost { return }
            Task { @MainActor in
                // Re-check: a recording may have started, or the panel closed, meanwhile.
                guard let self, self.wantsRunning, !self.micRequired.contains("vlog") else { return }
                self.configure(with: device)
            }
        }
    }

    /// The camera stopped working: show the message, then try to bring it back a few times
    /// (errors like another app grabbing the camera often come without an unplug event).
    private func cameraLost() {
        sessionLost = true
        refresh()
        guard !micRequired.contains("vlog"), recoveryAttempts < 3 else { return }
        recoveryAttempts += 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            self.recoverIfNeeded()
        }
    }

    // MARK: - Private

    private func refresh() {
        cameras = Self.discoverCameras()
        let fresh = CameraAccess.from(status: AVCaptureDevice.authorizationStatus(for: .video),
                                      hasDevice: !cameras.isEmpty)
        // Keep showing the problem until the camera is actually running again.
        access = (sessionLost && fresh == .allowed) ? .noCamera : fresh
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
            Task { @MainActor in
                guard let self, self.sessionLost else { return }
                self.sessionLost = false
                self.recoveryAttempts = 0
                self.refresh()
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
