import AppKit
import AVFoundation
import Observation
import CompactCore

/// Records the camera session to a `.mov` in ~/Movies/Compact via an `AVCaptureMovieFileOutput`.
/// The movie output is added when recording starts and removed after the file finishes (idle sessions stay light).
@MainActor @Observable
final class VlogRecorder {
    private(set) var state: RecordingState = .idle
    /// Called whenever `state` changes (used to re-evaluate the camera lifecycle and status item).
    @ObservationIgnored var onStateChange: ((RecordingState) -> Void)?

    @ObservationIgnored private let camera: CameraController
    @ObservationIgnored private var output: AVCaptureMovieFileOutput?
    @ObservationIgnored private var delegate: Delegate?
    @ObservationIgnored private var recordingID: UUID?
    @ObservationIgnored private var didStartRecording = false
    @ObservationIgnored private var currentURL: URL?
    /// The most recently saved video (drives the "Saved" note in the panel).
    private(set) var lastSaved: URL?
    @ObservationIgnored private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    init(camera: CameraController) { self.camera = camera }

    @ObservationIgnored private var isStarting = false

    func start() {
        guard !state.isActive, !isStarting else { return }
        isStarting = true
        Task { @MainActor in
            defer { isStarting = false }
            // Resolve mic permission first so the audio input is attached before recording begins.
            if !(await camera.ensureMicAccess()), !confirmRecordWithoutSound() { return }
            begin()
        }
    }

    /// Returns true if the user chose to record without sound.
    private func confirmRecordWithoutSound() -> Bool {
        let alert = NSAlert()
        alert.messageText = "No microphone access"
        alert.informativeText = "Compact can't use your microphone, so this vlog will have no sound. You can turn it on in System Settings → Privacy & Security → Microphone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Record Without Sound")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func begin() {
        guard !state.isActive else { return }
        let url: URL
        do {
            let folder = MediaLocation.folder(for: .vlog, home: FileManager.default.homeDirectoryForCurrentUser)
            url = try MediaLocation.uniqueURL(for: .vlog, in: folder, date: Date())
        } catch {
            fail("Compact couldn't save to your Movies folder: \(error.localizedDescription)")
            return
        }
        let output = AVCaptureMovieFileOutput()
        let id = UUID()
        self.output = output
        recordingID = id
        currentURL = url
        didStartRecording = false
        camera.requireMic("vlog")
        set(.recording(startedAt: Date(), url: url))   // camera must stay on from now
        Task { @MainActor in
            let failure = await camera.attachMovieOutput(output)
            guard self.recordingID == id else {
                if failure == nil { self.camera.detachMovieOutput(output) }
                return
            }
            if let failure {
                self.cleanup()
                self.fail(failure)
                return
            }
            if self.state == .stopping {
                // Stop was pressed before recording began: nothing was written, so just tidy up.
                self.finished(id: id, error: nil)
                return
            }
            let delegate = Delegate { [weak self] error in
                Task { @MainActor in self?.finished(id: id, error: error) }
            }
            self.delegate = delegate
            let started = await self.camera.startMovieRecording(output, to: url, delegate: delegate)
            guard self.recordingID == id else {
                if started { output.stopRecording() }
                return
            }
            guard started else {
                self.cleanup()
                self.fail("Compact couldn't start recording. Close any other app using the camera and try again.")
                return
            }
            self.didStartRecording = true
            if self.state == .stopping {
                // Stop was pressed while recording was starting: stop now and let the file finish.
                self.stopAndWatch(output, id: id)
            }
        }
    }

    /// Resolves once the video has finished saving (immediately if not recording). If stop is
    /// pressed while recording is still starting, this waits for it to start and then stops it,
    /// so the file is always finished properly.
    func stop() async {
        switch state {
        case .recording:
            set(.stopping)
            if didStartRecording, let output, let id = recordingID {
                stopAndWatch(output, id: id)
            }
            // Otherwise the start task sees `.stopping` and finishes things off when it's safe.
        case .stopping: break
        default: return
        }
        guard state == .stopping else { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }

    /// Stops the file output and, if it never confirms the file is finished, gives up after
    /// 10 seconds instead of staying stuck in "stopping" with the camera on.
    private func stopAndWatch(_ output: AVCaptureMovieFileOutput, id: UUID) {
        output.stopRecording()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard self.recordingID == id, self.state == .stopping else { return }
            self.cleanup()
            self.fail("Compact couldn't finish saving the video. It may be incomplete.")
        }
    }

    private func finished(id: UUID?, error: Error?) {
        guard state.isActive, id == recordingID else { return }
        // AVFoundation reports some errors (e.g. disk full) with the file still finished OK.
        let fileOK = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        let url = currentURL
        cleanup()
        let outcome = RecordingOutcome(errorMessage: error?.localizedDescription, fileFinishedOK: fileOK,
                                       fileExists: url.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        switch outcome {
        case .failed(let reason):
            fail("Recording stopped: \(reason)")
        case .stoppedEarly(let reason):
            lastSaved = url
            set(.idle)
            resumeWaiters()
            showAlert(title: "Recording stopped early",
                      message: "\(reason)\n\nWhat was recorded so far was saved to Movies → Compact.")
            return
        case .saved:
            lastSaved = url
            set(.idle)
        case .nothingRecorded:
            set(.idle)
        }
        resumeWaiters()
    }

    private func resumeWaiters() {
        let waiters = finishWaiters
        finishWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func cleanup() {
        if let output { camera.detachMovieOutput(output) }
        output = nil
        delegate = nil
        recordingID = nil
        currentURL = nil
        didStartRecording = false
        camera.releaseMic("vlog")
    }

    private func fail(_ message: String) {
        set(.failed(message: message))
        resumeWaiters()   // before the alert, so a pending quit isn't held up
        showAlert(title: "Recording failed", message: message)
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    private func set(_ new: RecordingState) {
        state = new
        onStateChange?(new)
    }

    private final class Delegate: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var done: ((Error?) -> Void)?
        init(done: @escaping (Error?) -> Void) { self.done = done }

        func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                        from connections: [AVCaptureConnection], error: Error?) {
            lock.lock(); let cb = done; done = nil; lock.unlock()   // resume exactly once
            cb?(error)
        }
    }
}
