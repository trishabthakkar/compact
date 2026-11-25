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

    /// Later tasks append buttons here (snap, record, folder).
    private var controlsBar: some View {
        HStack(spacing: 12) {
            Button {
                camera.setMicMeter(enabled: !camera.micMeterOn)
            } label: {
                Image(systemName: camera.micMeterOn ? "mic.fill" : "mic")
            }
            .help("Mic check")
            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .frame(width: 320, height: 32)
    }
}
