import SwiftUI
import AppKit
import CompactCore

struct CameraPanelView: View {
    let camera: CameraController
    let recorder: VlogRecorder
    let store: SettingsStore
    /// Non-nil when hosted in the floating window: controls become a hover overlay and a close button appears.
    var onClose: (() -> Void)? = nil
    /// Opens the Settings window (from the ⚙︎ menu).
    var onOpenSettings: () -> Void = {}
    /// Set once the first-launch hint has been shown.
    /// Set by the app on first launch; the hint shows for a few seconds, then clears.
    @AppStorage("compact.showWelcomeHint") private var showWelcome = false
    /// A snap is being taken (waiting for the camera frame); blocks a second, overlapping snap.
    @MainActor private static var snapInFlight = false
    /// Short notes shown at the top of the view ("Saved…", "Couldn't take the snap").
    @State private var note: String?
    @State private var noteURL: URL?
    @State private var hovering = false
    /// The camera view's AppKit view, used to attach the snap pop-up just below it.
    @State private var anchor: NSView?
    /// Photo Booth-style white flash over the video when a snap is taken.
    @State private var flash: Double = 0

    var body: some View {
        Group {
            if onClose != nil { floatingBody } else { popoverBody }
        }
        .background(ViewAnchor { anchor = $0 })
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                if showWelcome {
                    banner(Text("Compact lives up here in your menu bar. Use ⚙︎ for settings."))
                }
                if let note {
                    banner(HStack(spacing: 8) {
                        Text(note)
                        if let noteURL {
                            Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([noteURL]) }
                                .buttonStyle(.borderless).foregroundStyle(.white).underline()
                        }
                    })
                }
            }
            .padding(.top, 8)
        }
        .onChange(of: recorder.lastSaved) { _, url in
            guard let url else { return }
            showNote("Saved to Movies → Compact", url: url)
        }
        .onChange(of: showWelcome, initial: true) { _, showing in
            guard showing else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { withAnimation { showWelcome = false } }
        }
    }

    private var floatingBody: some View {
        let showControls = hovering || recorder.state.isActive || store.settings.alwaysShowControls
        let shape = store.settings.shape
        let size = contentSize(size: store.settings.size, shape: shape)
        let radius = CompactCore.cornerRadius(shape: shape, in: size)
        let round = shape == .circle || shape == .capsule
        return preview(width: size.width, height: size.height, meterBottomInset: round ? size.height * 0.25 + 40 : 0,
                       meterSideInset: round ? radius * 0.5 : 0)
            .overlay(alignment: .bottom) {
                if showControls {
                    if round {
                        controlsBar(compact: true)
                            .padding(.horizontal, 12)
                            .background(.black.opacity(0.55), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(.bottom, size.height * 0.25)
                    } else {
                        controlsBar(compact: false).background(.black.opacity(0.55)).foregroundStyle(.white)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button { onClose?() } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .padding(round ? radius * 0.3 : 8)
                    .help("Close")
                    .accessibilityLabel("Close")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(HoverTracker { hovering = $0 })
            .background(SpaceKeyMonitor(onSpace: snap))
    }

    /// Buttons float over the bottom of the video: shown while the pointer is over it,
    /// and always while recording so the stop button and timer stay visible.
    private var popoverBody: some View {
        let showControls = hovering || recorder.state.isActive || store.settings.alwaysShowControls
        let size = contentSize(size: store.settings.popoverSize, shape: .rounded)
        return preview(width: size.width, height: size.height, meterBottomInset: showControls ? 36 : 0)
            .overlay(alignment: .bottom) {
                if showControls {
                    controlsBar(compact: false)
                        .frame(height: 32)
                        .background(.black.opacity(0.55))
                        .foregroundStyle(.white)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: showControls)
            .background(HoverTracker { hovering = $0 })
            .background(SpaceKeyMonitor(onSpace: snap))
    }

    private func preview(width: CGFloat, height: CGFloat, meterBottomInset: CGFloat = 0, meterSideInset: CGFloat = 0) -> some View {
        ZStack {
            Color.black
            CameraPreviewView(session: camera.session)
                .scaleEffect(x: store.settings.mirrorPreview ? -1 : 1, y: 1)
            if let message = camera.access.message {
                VStack(spacing: 10) {
                    Text(message)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    if camera.access == .denied {
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                .padding(16)
                .background(.black.opacity(0.7))
            }
        }
        .frame(width: width, height: height)
        .overlay { Color.white.opacity(flash).allowsHitTesting(false) }
        .overlay(alignment: .bottom) {
            micMeter.padding(.horizontal, meterSideInset).padding(.bottom, meterBottomInset)
        }
    }

    @ViewBuilder private var micMeter: some View {
        if camera.micMeterOn {
            Group {
                if camera.micDenied {
                    VStack(spacing: 4) {
                        Text("Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .controlSize(.small)
                    }
                } else {
                    AudioMeterView(level: camera.audioLevel)
                }
            }
            .padding(8)
            .background(.black.opacity(0.55))
        }
    }

    /// macOS's own camera shutter click (falls back to Tink if it isn't there).
    private static let shutterSound: NSSound? =
        NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Shutter.aif",
                byReference: true) ?? NSSound(named: "Tink")

    private func banner(_ content: some View) -> some View {
        content
            .font(.caption).foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.black.opacity(0.7), in: Capsule())
            .transition(.opacity)
    }

    private func showNote(_ text: String, url: URL? = nil) {
        withAnimation { note = text; noteURL = url }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if note == text { withAnimation { note = nil; noteURL = nil } }
        }
    }

    private func snap() {
        // No camera picture, no snap (and no flash pretending it worked).
        guard camera.access == .allowed else { NSSound.beep(); return }
        guard !Self.snapInFlight else { return }   // one snap at a time
        if store.settings.snapShutterSound {
            Self.shutterSound?.stop()   // restart if a previous click is still playing
            Self.shutterSound?.play()
        }
        flash = 1
        withAnimation(.easeOut(duration: 0.5)) { flash = 0 }
        let includeDate = store.settings.snapIncludesDate
        let mirror = store.settings.mirrorPreview
        let startFrame = store.settings.defaultSnapFrame
        Self.snapInFlight = true
        Task { @MainActor in
            defer { Self.snapInFlight = false }
            guard let frame = await camera.captureFrame() else {
                showNote("Couldn't take the snap. Try again.")
                return
            }
            // Match what you see: mirror the snap whenever the live preview is mirrored.
            let photo = mirror ? (mirroredHorizontally(frame) ?? frame) : frame
            guard let anchor else { return }
            SnapPopoverController(image: photo, includeDate: includeDate, date: Date(), frame: startFrame).show(below: anchor)
        }
    }

    @ViewBuilder private func recordButton(compact: Bool) -> some View {
        if case .recording(let startedAt, _) = recorder.state {
            Button { Task { await recorder.stop() } } label: {
                HStack(spacing: 3) {
                    Image(systemName: "stop.circle.fill")
                    if !camera.micAttached && !camera.micSettingUp {
                        Image(systemName: "mic.slash.fill")
                            .help("Recording without sound: no microphone is connected")
                            .accessibilityLabel("Recording without sound")
                    }
                    TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                        Text(elapsedLabel(from: startedAt, to: ctx.date))
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundStyle(.red)
            }
            .help("Stop recording")
            .accessibilityLabel("Stop recording")
        } else {
            Button { recorder.start() } label: { Image(systemName: "record.circle") }
                .disabled(recorder.state == .stopping || camera.access != .allowed)
                .help("Record a vlog")
                .accessibilityLabel("Record a vlog")
        }
    }

    /// ⚙︎ menu: Settings, the save folders and Quit, so nothing depends on finding the right-click menu.
    private var moreMenu: some View {
        Menu {
            Button("Settings…", action: onOpenSettings)
            Button("Open Snaps Folder") { openFolder(.snap) }
            Button("Open Vlogs Folder") { openFolder(.vlog) }
            Divider()
            Button("Quit Compact") { NSApp.terminate(nil) }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings and more")
        .accessibilityLabel("Settings and more")
    }

    private func openFolder(_ kind: MediaKind) {
        let folder = MediaLocation.folder(for: kind, home: FileManager.default.homeDirectoryForCurrentUser)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    /// Controls shared by the popover and floating layouts.
    private func controlsBar(compact: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                camera.setMicMeter(enabled: !camera.micMeterOn)
            } label: {
                Image(systemName: camera.micMeterOn ? "mic.fill" : "mic")
            }
            .help("Mic check")
            .accessibilityLabel(camera.micMeterOn ? "Turn off mic check" : "Turn on mic check")
            Button { snap() } label: { Image(systemName: "camera.shutter.button") }
                .help("Snap (Space)")
                .accessibilityLabel("Take a snap")
            recordButton(compact: compact)
            if !compact { Spacer() }
            moreMenu
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(maxWidth: compact ? nil : .infinity, minHeight: 32, maxHeight: 32)
    }
}


/// Fires `onSpace` for Space key-downs while this view's window is key and no text field is editing.
private struct SpaceKeyMonitor: NSViewRepresentable {
    let onSpace: () -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView(onSpace: onSpace) }
    func updateNSView(_ view: MonitorView, context: Context) { view.onSpace = onSpace }

    final class MonitorView: NSView {
        var onSpace: () -> Void
        private var monitor: Any?
        init(onSpace: @escaping () -> Void) { self.onSpace = onSpace; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let win = self.window, win.isKeyWindow, event.window === win,
                      event.keyCode == 49, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                      !(win.firstResponder is NSText) else { return event }
                if !event.isARepeat { self.onSpace() }
                return nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}


/// Reliable hover regardless of key/active state (SwiftUI .onHover can miss on non-key panels).
private struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void
    func makeNSView(context: Context) -> TrackerView { TrackerView(onChange: onChange) }
    func updateNSView(_ view: TrackerView, context: Context) { view.onChange = onChange }

    final class TrackerView: NSView {
        var onChange: (Bool) -> Void
        init(onChange: @escaping (Bool) -> Void) { self.onChange = onChange; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError() }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// Reports the plain (non-flipped) NSView behind a SwiftUI view, so AppKit pop-ups can attach to it.
private struct ViewAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
