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
    @ObservationIgnored private var finishWaiters: [CheckedContinuation<Void, Never>] = []

    init(camera: CameraController) { self.camera = camera }

    func start() {
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
        didStartRecording = false
        camera.requireMic("vlog")
        set(.recording(startedAt: Date(), url: url))   // camera must stay on from now
        Task { @MainActor in
            let failure = await camera.attachMovieOutput(output)
            guard self.recordingID == id, case .recording = self.state else {
                // Stopped/failed before we got here: this task owns the leftover attachment.
                if failure == nil { self.camera.detachMovieOutput(output) }
                return
            }
            if let failure {
                self.cleanup()
                self.fail(failure)
                return
            }
            let delegate = Delegate { [weak self] error in
                Task { @MainActor in self?.finished(id: id, error: error) }
            }
            self.delegate = delegate
            self.didStartRecording = true
            output.startRecording(to: url, recordingDelegate: delegate)
        }
    }

    /// Resolves once the file has been finalized (immediately if not recording).
    func stop() async {
        switch state {
        case .recording:
            set(.stopping)
            if didStartRecording, let output {
                output.stopRecording()   // always wait for the delegate once started
            } else {
                finished(id: recordingID, error: nil)   // never started: the start task detaches the output
            }
        case .stopping: break
        default: return
        }
        guard state == .stopping else { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }

    private func finished(id: UUID?, error: Error?) {
        guard state.isActive, id == recordingID else { return }
        // AVFoundation reports some errors (e.g. disk full) with the file still finished OK.
        let fileOK = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        let started = didStartRecording
        cleanup()
        if let error, !fileOK, started {
            fail("Recording stopped: \(error.localizedDescription)")
        } else {
            set(.idle)
        }
        let waiters = finishWaiters
        finishWaiters = []
        waiters.forEach { $0.resume() }
    }

    private func cleanup() {
        if let output { camera.detachMovieOutput(output) }
        output = nil
        delegate = nil
        recordingID = nil
        didStartRecording = false
        camera.releaseMic("vlog")
    }

    private func fail(_ message: String) {
        set(.failed(message: message))
        let alert = NSAlert()
        alert.messageText = "Recording failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        let waiters = finishWaiters
        finishWaiters = []
        waiters.forEach { $0.resume() }   // resume before the modal so a pending quit isn't held up
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
