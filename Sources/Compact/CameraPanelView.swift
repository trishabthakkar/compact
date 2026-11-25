import SwiftUI
import AppKit
import CompactCore

struct CameraPanelView: View {
    let camera: CameraController
    let recorder: VlogRecorder
    let store: SettingsStore
    /// Non-nil when hosted in the floating window: controls become a hover overlay and a close button appears.
    var onClose: (() -> Void)? = nil
    @State private var hovering = false

    var body: some View {
        if onClose != nil { floatingBody } else { popoverBody }
    }

    private var floatingBody: some View {
        let shape = store.settings.shape
        let size = contentSize(size: store.settings.size, shape: shape)
        let radius = CompactCore.cornerRadius(shape: shape, in: size)
        let round = shape == .circle || shape == .capsule
        return preview(width: size.width, height: size.height, meterBottomInset: round ? size.height * 0.25 + 40 : 0,
                       meterSideInset: round ? radius * 0.5 : 0)
            .overlay(alignment: .bottom) {
                if hovering {
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
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .background(HoverTracker { hovering = $0 })
            .background(SpaceKeyMonitor(onSpace: snap))
    }

    private var popoverBody: some View {
        VStack(spacing: 0) {
            preview(width: 384, height: 216)
            controlsBar(compact: false).frame(width: 384, height: 32)
        }
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

    private func snap() {
        NSSound(named: "Tink")?.play()
        let includeDate = store.settings.snapIncludesDate
        Task { @MainActor in
            guard let frame = await camera.captureFrame() else { NSSound.beep(); return }
            SnapWindowController(image: frame, includeDate: includeDate, date: Date()).show()
        }
    }

    @ViewBuilder private func recordButton(compact: Bool) -> some View {
        if case .recording(let startedAt, _) = recorder.state {
            Button { Task { await recorder.stop() } } label: {
                HStack(spacing: 3) {
                    Image(systemName: "stop.circle.fill")
                    TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                        Text(elapsedLabel(from: startedAt, to: ctx.date))
                            .font(.caption.monospacedDigit())
                    }
                }
                .foregroundStyle(.red)
            }
            .help("Stop recording")
        } else {
            Button { recorder.start() } label: { Image(systemName: "record.circle") }
                .disabled(recorder.state == .stopping || camera.access != .allowed)
                .help("Record a vlog")
        }
    }

    private func openVlogFolder() {
        let folder = MediaLocation.folder(for: .vlog, home: FileManager.default.homeDirectoryForCurrentUser)
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
            Button { snap() } label: { Image(systemName: "camera.shutter.button") }
                .help("Snap (Space)")
            recordButton(compact: compact)
            if !compact { Spacer() }
            if !compact {   // the round-shape cluster is ~90pt wide; folder lives in the popover/rect bar
                Button { openVlogFolder() } label: { Image(systemName: "folder") }
                    .help("Open vlog folder")
            }
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
