import AppKit
import Observation
import CompactCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = SettingsStore()
    private lazy var camera = CameraController(store: store)
    private lazy var recorder = VlogRecorder(camera: camera)
    private lazy var presentation = PresentationController(camera: camera, recorder: recorder, store: store)
    private var statusItem: StatusItemController?
    private let hotkey = GlobalHotkey()
    private var lastHotkey: Hotkey?
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(store: store, camera: camera, recorder: recorder,
                     onIconChanged: { [weak self] in self?.statusItem?.refreshIcon() },
                     onWindowModeChanged: { [weak self] in self?.presentation.hide() })
    }
    private var panelVisible = false
    private var cameraRunning = false

    /// Re-evaluated on both panel visibility and recording-state changes.
    private func updateCamera() {
        let run = shouldRunCamera(panelVisible: panelVisible, isRecording: recorder.state.isActive)
        // Only act on changes: start() reconfigures inputs, which must not happen mid-recording.
        guard run != cameraRunning else { return }
        cameraRunning = run
        if run {
            camera.start()
        } else {
            camera.stop()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        presentation.onVisibilityChange = { [weak self] visible in
            self?.panelVisible = visible
            self?.updateCamera()
        }
        recorder.onStateChange = { [weak self] state in
            self?.statusItem?.setRecording(state.isActive)
            self?.updateCamera()
        }
        statusItem = StatusItemController(store: store) { [weak self] in
            guard let self else { return }
            self.presentation.toggle(relativeTo: self.statusItem?.button)
        }
        statusItem?.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        applyHotkey()
        observeHotkey()
    }

    private func applyHotkey() {
        lastHotkey = store.settings.hotkey
        hotkey.register(lastHotkey) { [weak self] in
            guard let self else { return }
            self.presentation.toggle(relativeTo: self.statusItem?.button)
        }
    }

    private func observeHotkey() {
        withObservationTracking {
            _ = store.settings.hotkey
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if self.store.settings.hotkey != self.lastHotkey { self.applyHotkey() }
                self.observeHotkey()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard recorder.state.isActive else { return .terminateNow }
        Task { @MainActor in
            await recorder.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
