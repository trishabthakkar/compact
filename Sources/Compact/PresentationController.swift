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
    var onVisibilityChange: ((Bool) -> Void)?

    var isVisible: Bool { popover.isShown || floating.isVisible }

    init(camera: CameraController, recorder: VlogRecorder, store: SettingsStore) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 272)
        popover.contentViewController = NSHostingController(
            rootView: CameraPanelView(camera: camera, recorder: recorder, store: store))
        popover.delegate = self

        let host = NSHostingView(rootView: CameraPanelView(camera: camera, recorder: recorder, store: store, onClose: { [weak self] in
            self?.hide()
        }))
        host.sizingOptions = []
        host.layer?.backgroundColor = .clear
        floating = FloatingWindowController(store: store, content: host)
    }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if button != nil { anchor = button }
        isVisible ? hide() : show()
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
            onVisibilityChange?(true)
        }
    }

    func hide() {
        if floating.isVisible {
            floating.hide()
            onVisibilityChange?(false)
        } else if popover.isShown {
            popover.performClose(nil)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }
}
