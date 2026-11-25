import AppKit
import SwiftUI
import CompactCore

@MainActor
final class SnapWindowController: NSObject, NSWindowDelegate {
    private let image: CGImage
    private let includeDate: Bool
    private let date: Date
    private var window: NSWindow?
    private var savedURL: URL?
    private let model = SnapWindowModel()
    private static var open: [SnapWindowController] = []

    init(image: CGImage, includeDate: Bool, date: Date) {
        self.image = image
        self.includeDate = includeDate
        self.date = date
        super.init()
    }

    func show() {
        let root = SnapWindowContent(
            card: SnapCardView(image: image, includeDate: includeDate, date: date),
            model: model,
            onSave: { [weak self] in self?.save() },
            onDiscard: { [weak self] in self?.window?.close() },
            onReveal: { [weak self] in
                if let url = self?.savedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            })
        let host = NSHostingController(rootView: root)
        let w = NSWindow(contentViewController: host)
        w.title = "Snap"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        window = w
        Self.open.append(self)
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        Self.open.removeAll { $0 === self }
    }

    private func save() {
        let card = SnapCardView(image: image, includeDate: includeDate, date: date)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        do {
            guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let folder = MediaLocation.folder(for: .snap, home: FileManager.default.homeDirectoryForCurrentUser)
            let url = try MediaLocation.uniqueURL(for: .snap, in: folder, date: Date())
            try png.write(to: url)
            savedURL = url
            model.saved = true
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't save the snap"
            alert.runModal()
        }
    }
}

@Observable
final class SnapWindowModel { var saved = false }

private struct SnapWindowContent: View {
    let card: SnapCardView
    let model: SnapWindowModel
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            card.shadow(radius: 4, y: 2)
            HStack {
                Button("Discard", action: onDiscard)
                Spacer()
                if model.saved { Button("Show in Finder", action: onReveal) }
                Button("Save", action: onSave).keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }
}
