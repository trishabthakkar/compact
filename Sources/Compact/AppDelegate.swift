import AppKit
import CompactCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private lazy var camera = CameraController(store: store)
    private lazy var presentation = PresentationController(camera: camera, store: store)
    private var statusItem: StatusItemController?
    private var isRecording = false  // wired up in the recording task

    func applicationDidFinishLaunching(_ notification: Notification) {
        presentation.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            if shouldRunCamera(panelVisible: visible, isRecording: self.isRecording) {
                self.camera.start()
            } else {
                self.camera.stop()
            }
        }
        statusItem = StatusItemController(store: store) { [weak self] in
            guard let self else { return }
            self.presentation.toggle(relativeTo: self.statusItem?.button)
        }
    }
}
