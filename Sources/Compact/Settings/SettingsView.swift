import AppKit
import ServiceManagement
import SwiftUI
import CompactCore

struct SettingsView: View {
    let store: SettingsStore
    let camera: CameraController
    let recorder: VlogRecorder
    var onIconChanged: () -> Void
    var onWindowModeChanged: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private func binding<T>(_ kp: WritableKeyPath<CompactCore.Settings, T>, then: (() -> Void)? = nil) -> Binding<T> {
        Binding(get: { store.settings[keyPath: kp] },
                set: { v in store.update { $0[keyPath: kp] = v }; then?() })
    }

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("Shortcut") { ShortcutRecorderView(hotkey: binding(\.hotkey)) }
                LabeledContent("Menu bar icon") {
                    HStack(spacing: 6) {
                        ForEach(MenuBarIcon.allCases, id: \.self) { icon in
                            let selected = store.settings.menuBarIcon == icon
                            Button {
                                store.update { $0.menuBarIcon = icon }
                                onIconChanged()
                            } label: {
                                Image(systemName: icon.symbolName)
                                    .frame(width: 28, height: 24)
                                    .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(icon.rawValue)
                        }
                    }
                }
            }
            Section("Camera") {
                Picker("Camera", selection: Binding(
                    get: { store.settings.cameraID ?? AVDefault.camera(camera) },
                    set: { camera.selectCamera(id: $0) })) {
                    ForEach(camera.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                Picker("Microphone", selection: Binding(
                    get: { store.settings.microphoneID ?? AVDefault.microphone(camera) },
                    set: { camera.selectMicrophone(id: $0) })) {
                    ForEach(camera.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                }
                .disabled(recorder.state.isActive)
                if recorder.state.isActive {
                    Text("Can't change while recording").font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Mirror preview", isOn: binding(\.mirrorPreview))
            }
            Section("Window") {
                Picker("Style", selection: binding(\.windowMode, then: onWindowModeChanged)) {
                    Text("Popover").tag(WindowMode.popover)
                    Text("Floating window").tag(WindowMode.floating)
                }
                Picker("Shape", selection: binding(\.shape)) {
                    ForEach(WindowShape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Size", selection: binding(\.size)) {
                    ForEach(WindowSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Picker("Position", selection: binding(\.position)) {
                    ForEach(WindowPosition.allCases, id: \.self) { Text(Self.positionName($0)).tag($0) }
                }
            }
            Section("Notch") {
                let hasNotch = NotchTriggerController.hasNotch
                Toggle("Click the notch to open Compact", isOn: binding(\.notchTriggerEnabled))
                    .disabled(!hasNotch)
                if !hasNotch {
                    Text("This Mac's display has no notch").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Snaps") {
                Toggle("Include date", isOn: binding(\.snapIncludesDate))
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 620)
        .onAppear {
            camera.refreshDevices()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private static func positionName(_ p: WindowPosition) -> String {
        switch p {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .center: "Center"
        case .remembered: "Remember last position"
        }
    }
}

import AVFoundation
private enum AVDefault {
    @MainActor static func camera(_ c: CameraController) -> String {
        AVCaptureDevice.default(for: .video)?.uniqueID ?? c.cameras.first?.uniqueID ?? ""
    }
    @MainActor static func microphone(_ c: CameraController) -> String {
        AVCaptureDevice.default(for: .audio)?.uniqueID ?? c.microphones.first?.uniqueID ?? ""
    }
}
