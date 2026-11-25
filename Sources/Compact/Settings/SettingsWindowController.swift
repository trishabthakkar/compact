import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let makeView: () -> SettingsView

    init(makeView: @escaping () -> SettingsView) { self.makeView = makeView }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 560),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Compact Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: makeView())
            w.center()
            window = w
        }
        // Rebuild the view each time so device lists and login-item status are fresh.
        window?.contentView = NSHostingView(rootView: makeView())
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

