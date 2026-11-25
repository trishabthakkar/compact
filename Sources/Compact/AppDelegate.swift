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
    private lazy var notch = NotchTriggerController { [weak self] in
        guard let self else { return }
        self.presentation.toggle(relativeTo: self.statusItem?.button)
    }
    private var lastHotkey: Hotkey?
    private lazy var settingsWindow = SettingsWindowController { [unowned self] in
        SettingsView(store: store, camera: camera, recorder: recorder, hotkey: hotkey,
                     onIconChanged: { [weak self] in self?.statusItem?.refreshIcon() },
                     onWindowModeChanged: { [weak self] in self?.presentation.hide() })
    }
    private var panelVisible = false
    private var cameraRunning = false
    // Screen sleep, session switch-out and lock each make the panel effectively invisible.
    private var screensAsleep = false
    private var sessionInactive = false
    private var screenLocked = false
    private var screenAvailable: Bool { !screensAsleep && !sessionInactive && !screenLocked }

    /// Re-evaluated on both panel visibility and recording-state changes.
    private func updateCamera() {
        let run = shouldRunCamera(panelVisible: panelVisible, isRecording: recorder.state.isActive,
                                screenAvailable: screenAvailable)
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
        camera.onAccessGrantedAfterPanelClosed = { [weak self] in self?.presentation.show() }
        observeScreenAvailability()
        statusItem = StatusItemController(store: store) { [weak self] in
            guard let self else { return }
            self.presentation.toggle(relativeTo: self.statusItem?.button)
        }
        statusItem?.onOpenSettings = { [weak self] in self?.settingsWindow.show() }
        applyHotkey()
        observeHotkey()
        notch.update(enabled: store.settings.notchTriggerEnabled)
        observeNotch()
    }

    private func observeScreenAvailability() {
        let ws = NSWorkspace.shared.notificationCenter
        let dc = DistributedNotificationCenter.default()
        func watch(_ center: NotificationCenter, _ name: Notification.Name, _ apply: @escaping (AppDelegate) -> Void) {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    apply(self)
                    self.updateCamera()
                }
            }
        }
        watch(ws, NSWorkspace.screensDidSleepNotification) { $0.screensAsleep = true }
        watch(ws, NSWorkspace.screensDidWakeNotification) { $0.screensAsleep = false }
        watch(ws, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionInactive = true }
        watch(ws, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionInactive = false }
        watch(dc, Notification.Name("com.apple.screenIsLocked")) { $0.screenLocked = true }
        watch(dc, Notification.Name("com.apple.screenIsUnlocked")) { $0.screenLocked = false }
    }

    private func observeNotch() {
        withObservationTracking {
            _ = store.settings.notchTriggerEnabled
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.notch.update(enabled: self.store.settings.notchTriggerEnabled)
                self.observeNotch()
            }
        }
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
        // Finish the file, but never let a stuck recorder block quitting forever.
        var replied = false
        let reply = {
            guard !replied else { return }
            replied = true
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        Task { @MainActor in
            await recorder.stop()
            reply()
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            reply()
        }
        return .terminateLater
    }
}
