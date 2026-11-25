import SwiftUI
import AppKit
import CompactCore

struct CameraPanelView: View {
    let camera: CameraController
    let store: SettingsStore

    var body: some View {
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
    }
}
