import AppKit
import CompactCore

/// A transparent click target sitting exactly over the camera notch.
private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NotchClickView: NSView {
    var onClick: () -> Void = {}
    override func mouseDown(with event: NSEvent) { onClick() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchTriggerController {
    private let onClick: () -> Void
    private var enabled = false
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?

    init(onClick: @escaping () -> Void) { self.onClick = onClick }

    /// The notch rect (global screen coordinates) of the first screen that has one.
    static func currentNotchRect() -> (screen: NSScreen, rect: CGRect)? {
        for screen in NSScreen.screens {
            if let r = notchRect(screenFrame: screen.frame,
                                 leftArea: screen.auxiliaryTopLeftArea,
                                 rightArea: screen.auxiliaryTopRightArea) {
                return (screen, r)
            }
        }
        return nil
    }

    static var hasNotch: Bool { currentNotchRect() != nil }

    func update(enabled: Bool) {
        self.enabled = enabled
        if enabled, observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuild() }
            }
        } else if !enabled, let o = observer {
            NotificationCenter.default.removeObserver(o)
            observer = nil
        }
        rebuild()
    }

    private func rebuild() {
        panel?.orderOut(nil)
        panel = nil
        guard enabled, let (_, rect) = Self.currentNotchRect() else { return }
        let p = NotchPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        let view = NotchClickView(frame: NSRect(origin: .zero, size: rect.size))
        view.onClick = onClick
        p.contentView = view
        p.setFrame(rect, display: false)
        p.orderFrontRegardless()
        panel = p
    }
}
