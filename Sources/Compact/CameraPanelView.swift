import SwiftUI
import AppKit
import CompactCore

struct CameraPanelView: View {
    let camera: CameraController
    let store: SettingsStore

    var body: some View {
        VStack(spacing: 0) {
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
        .frame(width: 320, height: 240)
        .overlay(alignment: .bottom) { micMeter }
        controlsBar
        }
        .background(SpaceKeyMonitor(onSpace: snap))
    }

    @ViewBuilder private var micMeter: some View {
        if camera.micMeterOn {
            Group {
                if camera.micDenied {
                    Text("Microphone access is off. Turn it on in System Settings → Privacy & Security → Microphone.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
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

    /// Later tasks append buttons here (snap, record, folder).
    private var controlsBar: some View {
        HStack(spacing: 12) {
            Button {
                camera.setMicMeter(enabled: !camera.micMeterOn)
            } label: {
                Image(systemName: camera.micMeterOn ? "mic.fill" : "mic")
            }
            .help("Mic check")
            Button { snap() } label: { Image(systemName: "camera.shutter.button") }
                .help("Snap (Space)")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(width: 320, height: 32)
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
                self.onSpace()
                return nil
            }
        }

        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
