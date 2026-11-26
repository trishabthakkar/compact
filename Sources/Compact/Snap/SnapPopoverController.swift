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
    private static var current: SnapPopoverController? {
        didSet { onUnsavedChange?(hasUnsavedSnap) }
    }
    /// Told whenever a snap starts or stops waiting to be saved.
    static var onUnsavedChange: ((Bool) -> Void)?

    /// True while a snap is showing that hasn't been saved yet.
    static var hasUnsavedSnap: Bool { current.map { !$0.model.saved } ?? false }

    /// A small side-to-side wiggle, used when you try to close or re-snap with a snap unsaved.
    static func shakeCurrent() {
        guard let model = current?.model else { return }
        withAnimation(.linear(duration: 0.4)) { model.shakes += 1 }
    }
    private var outsideClickMonitors: [Any] = []

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

    /// Opens the snap below `anchor` (the camera view). Callers check `hasUnsavedSnap` first,
    /// so this only ever replaces a snap that was already saved.
    func show(below anchor: NSView) {
        guard anchor.window?.isVisible == true else { return }   // the camera view closed meanwhile
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
        stopOutsideClickMonitoring()
        if Self.current === self { Self.current = nil }
    }

    // MARK: - Closing a saved snap on outside clicks

    /// Once the snap is saved, any click outside this pop-up closes it. (An unsaved snap stays
    /// until you Save or Discard, so it isn't lost by accident.)
    private func startOutsideClickMonitoring() {
        stopOutsideClickMonitoring()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }) {
            outsideClickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, NSApp.modalWindow == nil,
                      event.window !== self.popover.contentViewController?.view.window else { return }
                self.popover.performClose(nil)
            }
            return event
        }) {
            outsideClickMonitors.append(local)
        }
    }

    private func stopOutsideClickMonitoring() {
        outsideClickMonitors.forEach { NSEvent.removeMonitor($0) }
        outsideClickMonitors = []
    }

    private func save() {
        guard !model.saved else { return }
        do {
            let output: CGImage
            if model.frame == .none {
                output = image   // just the photo, at the camera's full resolution
            } else {
                // Render the framed card so the photo inside keeps its full resolution.
                let card = SnapCardView(image: image, frame: model.frame, includeDate: includeDate, date: date)
                let renderer = ImageRenderer(content: card)
                renderer.scale = max(2, CGFloat(image.width) / SnapCardView.photoWidth)
                guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
                output = cg
            }
            guard let png = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let folder = MediaLocation.folder(for: .snap, home: FileManager.default.homeDirectoryForCurrentUser)
            let url = try MediaLocation.uniqueURL(for: .snap, in: folder, date: date)
            try png.write(to: url)
            savedURL = url
            model.saved = true
            Self.onUnsavedChange?(Self.hasUnsavedSnap)
            startOutsideClickMonitoring()   // saved: a click anywhere else now closes it
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
    var frame: SnapFrame = .default
    var shakes = 0
}

private struct SnapWindowContent: View {
    let image: CGImage
    let includeDate: Bool
    let date: Date
    @Bindable var model: SnapWindowModel
    let onSave: () -> Void
    let onDiscard: () -> Void
    let onReveal: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            SnapCardView(image: image, frame: model.frame, includeDate: includeDate, date: date)
                .shadow(radius: model.frame == .none ? 0 : 4, y: 2)
                .animation(.easeInOut(duration: 0.15), value: model.frame)
            Picker("Frame", selection: $model.frame) {
                ForEach(SnapFrame.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(model.saved)
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
        .frame(width: 384)
        .modifier(Shake(shakes: CGFloat(model.shakes)))
    }
}

/// Moves content side to side three times as `shakes` animates up by one.
private struct Shake: GeometryEffect {
    var shakes: CGFloat
    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 6), y: 0))
    }
}
