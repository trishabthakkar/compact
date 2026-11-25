import AppKit
import SwiftUI
import CompactCore

/// Shows a fresh snap in a pop-up attached just below the Compact camera view, where you can
/// draw on it and save or discard it. Only one snap pop-up is open at a time.
@MainActor
final class SnapPopoverController: NSObject, NSPopoverDelegate {
    private let image: CGImage
    private let includeDate: Bool
    private let date: Date
    private let popover = NSPopover()
    private var savedURL: URL?
    private let model = SnapWindowModel()
    private static var current: SnapPopoverController?

    init(image: CGImage, includeDate: Bool, date: Date) {
        self.image = image
        self.includeDate = includeDate
        self.date = date
        super.init()
    }

    /// True if `window` is the open snap pop-up (clicks there must not close the camera pop-up).
    static func owns(_ window: NSWindow?) -> Bool {
        guard let window, let current else { return false }
        return current.popover.contentViewController?.view.window === window
    }

    /// Closes the open snap pop-up, if any (used when the camera view it's attached to closes).
    static func closeCurrent() {
        current?.popover.performClose(nil)
    }

    /// Opens the snap below `anchor` (the camera view), replacing any snap already showing.
    func show(below anchor: NSView) {
        Self.current?.popover.performClose(nil)
        let root = SnapWindowContent(
            image: image, includeDate: includeDate, date: date,
            model: model,
            onSave: { [weak self] in self?.save() },
            onDiscard: { [weak self] in self?.popover.performClose(nil) },
            onReveal: { [weak self] in
                if let url = self?.savedURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            })
        popover.contentViewController = NSHostingController(rootView: root)
        popover.behavior = .applicationDefined   // closes via Discard, or when Compact closes
        popover.delegate = self
        Self.current = self
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        NSApp.activate()
    }

    func popoverDidClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }

    private func save() {
        guard !model.saved else { return }
        // Chrome-free card: strokes are in photo coordinates, so they land where they were drawn.
        let card = SnapCardView(image: image, includeDate: includeDate, date: date,
                                strokes: .constant(model.strokes), color: .red, drawingEnabled: false)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        do {
            guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let folder = MediaLocation.folder(for: .snap, home: FileManager.default.homeDirectoryForCurrentUser)
            let url = try MediaLocation.uniqueURL(for: .snap, in: folder, date: date)
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
final class SnapWindowModel {
    var saved = false
    var strokes: [MarkerStroke] = []
    var color: Color = .red
}

private struct SnapWindowContent: View {
    let image: CGImage
    let includeDate: Bool
    let date: Date
    @Bindable var model: SnapWindowModel
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onReveal: () -> Void

    private static let swatches: [(String, Color)] = [
        ("Black", .black), ("Red", .red), ("Blue", .blue), ("Green", .green), ("Yellow", .yellow)]

    var body: some View {
        VStack(spacing: 12) {
            SnapCardView(image: image, includeDate: includeDate, date: date,
                         strokes: $model.strokes, color: model.color, drawingEnabled: !model.saved)
                .shadow(radius: 4, y: 2)
            HStack(spacing: 8) {
                ForEach(Self.swatches, id: \.0) { name, color in
                    Button { model.color = color } label: {
                        Circle().fill(color)
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.gray.opacity(0.6), lineWidth: 1))
                            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2).padding(-3)
                                .opacity(model.color == color ? 1 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
                Spacer().frame(width: 8)
                Button("Undo") { _ = model.strokes.popLast() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.strokes.isEmpty || model.saved)
                Button("Clear") { model.strokes.removeAll() }
                    .disabled(model.strokes.isEmpty || model.saved)
            }
            HStack {
                Button("Discard", action: onDiscard)
                Spacer()
                if model.saved { Button("Show in Finder", action: onReveal) }
                Button(model.saved ? "Saved" : "Save", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.saved)
            }
        }
        .padding(16)
    }
}
