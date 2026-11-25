import AppKit
import CompactCore

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let store: SettingsStore
    private let onClick: () -> Void
    private var isRecording = false

    var onOpenSettings: (() -> Void)?
    var button: NSStatusBarButton? { statusItem.button }

    init(store: SettingsStore, onClick: @escaping () -> Void) {
        self.store = store
        self.onClick = onClick
        super.init()
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clicked(_:))
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshIcon()
    }

    func setRecording(_ on: Bool) {
        isRecording = on
        refreshIcon()
    }

    func refreshIcon() {
        let name = isRecording ? "record.circle.fill" : store.settings.menuBarIcon.symbolName
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Compact")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = isRecording ? .systemRed : nil
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { onClick(); return }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showMenu()
        } else {
            onClick()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let vlogs = NSMenuItem(title: "Open Vlogs Folder", action: #selector(openVlogs), keyEquivalent: "")
        vlogs.target = self
        menu.addItem(vlogs)
        let snaps = NSMenuItem(title: "Open Snaps Folder", action: #selector(openSnaps), keyEquivalent: "")
        snaps.target = self
        menu.addItem(snaps)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Compact", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openVlogs() { openFolder(.vlog) }
    @objc private func openSnaps() { openFolder(.snap) }

    /// Folders are created on first save, so make sure it exists before opening.
    private func openFolder(_ kind: MediaKind) {
        let folder = MediaLocation.folder(for: kind, home: FileManager.default.homeDirectoryForCurrentUser)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }
}
