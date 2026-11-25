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
        self.output = output
        camera.requireMic("vlog")
        let startedAt = Date()
        set(.recording(startedAt: startedAt, url: url))   // camera must stay on from now
        Task { @MainActor in
            if let message = await camera.attachMovieOutput(output) {
                self.cleanup()
                self.fail(message)
                return
            }
            guard case .recording = self.state else { return }
            let delegate = Delegate { [weak self] error in
                Task { @MainActor in self?.finished(error: error) }
            }
            self.delegate = delegate
            output.startRecording(to: url, recordingDelegate: delegate)
        }
    }

    /// Resolves once the file has been finalized (immediately if not recording).
    func stop() async {
        switch state {
        case .recording:
            set(.stopping)
            if let output, output.isRecording { output.stopRecording() } else { finished(error: nil) }
        case .stopping: break
        default: return
        }
        guard state == .stopping else { return }
        await withCheckedContinuation { finishWaiters.append($0) }
    }

    private func finished(error: Error?) {
        guard state.isActive else { return }
        // AVFoundation reports some errors (e.g. disk full) with the file still finished OK.
        let fileOK = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        cleanup()
        if let error, !fileOK {
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
