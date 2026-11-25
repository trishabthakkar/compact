import AppKit
import SwiftUI
import CompactCore

/// Shows/hides the camera panel. Popover only for now; floating window mode is added later.
@MainActor
final class PresentationController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private weak var anchor: NSStatusBarButton?
    var onVisibilityChange: ((Bool) -> Void)?

    var isVisible: Bool { popover.isShown }

    init(camera: CameraController, store: SettingsStore) {
        super.init()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 272)
        popover.contentViewController = NSHostingController(
            rootView: CameraPanelView(camera: camera, store: store))
        popover.delegate = self
    }

    func toggle(relativeTo button: NSStatusBarButton?) {
        if button != nil { anchor = button }
        isVisible ? hide() : show()
    }

    func show() {
        guard !isVisible, let button = anchor else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        onVisibilityChange?(true)
    }

    func hide() {
        guard isVisible else { return }
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }
}
