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
            image: image, includeDate: includeDate, date: date,
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
