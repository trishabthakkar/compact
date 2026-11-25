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
    private var appliedLayout: (WindowSize, WindowShape)?
    private var appliedPosition: WindowPosition?
    private var saveTask: Task<Void, Never>?

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
        observeSettings()  // single, permanent chain; ignores changes while hidden
    }

    func show() {
        guard !panel.isVisible else { return }
        applyGeometry(reposition: true)
        panel.orderFrontRegardless()
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
        appliedLayout = (s.size, s.shape)
        appliedPosition = s.position
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
                guard let self else { return }
                let st = self.store.settings
                if self.panel.isVisible {
                    if self.appliedPosition != st.position, st.position != .remembered {
                        self.applyGeometry(reposition: true)
                    } else if let a = self.appliedLayout, a != (st.size, st.shape) {
                        self.applyGeometry(reposition: false)
                    }
                    self.appliedPosition = st.position
                }
                self.observeSettings()
            }
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard !isPlacing, panel.isVisible else { return }
        // Debounce: persist once the drag has settled instead of on every mouse event.
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard let self, !Task.isCancelled, self.panel.isVisible else { return }
            let origin = self.panel.frame.origin
            self.store.update { $0.rememberedOrigin = origin }
        }
    }
}
