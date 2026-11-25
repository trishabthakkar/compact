import AppKit
import Observation
import CompactCore

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class FloatingWindowController: NSObject, NSWindowDelegate {
    private let store: SettingsStore
    private let panel: FloatingPanel
    private var isPlacing = false

    var isVisible: Bool { panel.isVisible }

    init(store: SettingsStore, content: NSView) {
        self.store = store
        panel = FloatingPanel(contentRect: .zero,
                              styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: true)
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = content
        panel.delegate = self
    }

    func show() {
        guard !panel.isVisible else { return }
        applyGeometry(reposition: true)
        panel.orderFrontRegardless()
        observeSettings()
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
    }

    private var screen: NSScreen {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? .main ?? NSScreen.screens[0]
    }

    private func applyGeometry(reposition: Bool) {
        let s = store.settings
        let size = contentSize(size: s.size, shape: s.shape)
        isPlacing = true
        defer { isPlacing = false }
        if reposition {
            let origin = windowOrigin(position: s.position, windowSize: size,
                                      visibleFrame: screen.visibleFrame, remembered: s.rememberedOrigin)
            panel.setFrame(CGRect(origin: origin, size: size), display: true)
        } else {
            // Keep the top-left corner fixed when resizing in place.
            let old = panel.frame
            panel.setFrame(CGRect(x: old.minX, y: old.maxY - size.height, width: size.width, height: size.height), display: true)
        }
        panel.invalidateShadow()
    }

    private func observeSettings() {
        withObservationTracking {
            _ = store.settings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                self.applyGeometry(reposition: false)
                self.observeSettings()
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isPlacing, panel.isVisible else { return }
        let origin = panel.frame.origin
        store.update { $0.rememberedOrigin = origin }
    }
}
