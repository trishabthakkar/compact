import AppKit
import SwiftUI
import CompactCore

/// Shows/hides the camera panel as a popover or a floating window, per `settings.windowMode`.
@MainActor
final class PresentationController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let store: SettingsStore
    private var floating: FloatingWindowController!
    private weak var anchor: NSStatusBarButton?
    private var isRecording = false
    private var hasUnsavedSnap = false
    private var outsideClickMonitors: [Any] = []
    var onVisibilityChange: ((Bool) -> Void)?
    /// Opens the Settings window; used by the ⚙︎ menu in the camera view.
    var onOpenSettings: (() -> Void)?

    var isVisible: Bool { popover.isShown || floating.isVisible }

    init(camera: CameraController, recorder: VlogRecorder, store: SettingsStore) {
        self.store = store
        super.init()
        // Closing on outside clicks is handled by our own monitors (see startOutsideClickMonitoring):
        // .transient is unreliable for a menu-bar-only app and can't be toggled while shown.
        popover.behavior = .applicationDefined
        popover.contentSize = NSSize(width: 384, height: 216)
        popover.contentViewController = NSHostingController(
            rootView: CameraPanelView(camera: camera, recorder: recorder, store: store,
                                      onOpenSettings: { [weak self] in self?.onOpenSettings?() }))
        popover.delegate = self

        let host = NSHostingView(rootView: CameraPanelView(camera: camera, recorder: recorder, store: store, onClose: { [weak self] in
            self?.closeOnPurpose()
        }, onOpenSettings: { [weak self] in self?.onOpenSettings?() }))
        host.sizingOptions = []
        host.layer?.backgroundColor = .clear
        floating = FloatingWindowController(store: store, content: host)
    }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if button != nil { anchor = button }
        isVisible ? closeOnPurpose() : show()
    }

    /// Opens Compact attached to the menu bar icon (used on first launch).
    func show(from button: NSStatusBarButton?) {
        if button != nil { anchor = button }
        show()
    }

    func show() {
        guard !isVisible else { return }
        if store.settings.windowMode == .floating {
            floating.show()
            onVisibilityChange?(true)
        } else {
            guard let button = anchor else { return }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            startOutsideClickMonitoring()
            onVisibilityChange?(true)
        }
    }

    /// While recording, the popover stays open when you click elsewhere (it would normally close).
    /// Clicking the menu bar icon still closes it on purpose.
    func setRecording(_ recording: Bool) {
        isRecording = recording
    }

    /// While a snap is unsaved, nothing closes Compact (closing would throw the snap away).
    func setUnsavedSnap(_ unsaved: Bool) {
        hasUnsavedSnap = unsaved
    }

    /// Menu bar icon, shortcut or ×: closes unless a snap is unsaved, in which case the snap
    /// gives a little shake to show why.
    func closeOnPurpose() {
        guard deliberateCloseAllowed(hasUnsavedSnap: hasUnsavedSnap) else {
            SnapPopoverController.shakeCurrent()
            return
        }
        hide()
    }

    func hide() {
        SnapPopoverController.closeCurrent()
        if floating.isVisible {
            floating.hide()
            onVisibilityChange?(false)
        } else if popover.isShown {
            popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        SnapPopoverController.closeCurrent()
        stopOutsideClickMonitoring()
        onVisibilityChange?(false)
    }

    // MARK: - Closing on outside clicks

    /// Closes the popover on any click outside it (in other apps, the desktop, or Compact's
    /// other windows) unless a recording is in progress. Clicks on the menu bar icon are left
    /// to `toggle`, and clicks in a modal alert are ignored.
    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.closeForOutsideClick() }
        }) {
            outsideClickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, NSApp.modalWindow == nil else { return }
                let window = event.window
                if window === self.popover.contentViewController?.view.window || window === self.anchor?.window
                    || SnapPopoverController.owns(window) { return }
                self.closeForOutsideClick()
            }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func stopOutsideClickMonitoring() {
        outsideClickMonitors.forEach { NSEvent.removeMonitor($0) }
        outsideClickMonitors = []
    }

    private func closeForOutsideClick() {
        guard outsideClickCloses(isRecording: isRecording, hasUnsavedSnap: hasUnsavedSnap), popover.isShown else { return }
        popover.performClose(nil)
    }
}
