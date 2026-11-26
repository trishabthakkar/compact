import AppKit
import AVFoundation
import ServiceManagement
import SwiftUI
import CompactCore

/// The pages in the Settings sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, camera, snaps, vlogs, floatingWindow, notch, micCheck, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .camera: "Camera"
        case .snaps: "Snaps"
        case .vlogs: "Vlogs"
        case .floatingWindow: "Floating Window"
        case .notch: "Notch Trigger"
        case .micCheck: "Mic Check"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .camera: "camera"
        case .snaps: "camera.shutter.button"
        case .vlogs: "record.circle"
        case .floatingWindow: "macwindow"
        case .notch: "rectangle.topthird.inset.filled"
        case .micCheck: "waveform"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    let store: SettingsStore
    let camera: CameraController
    let recorder: VlogRecorder
    let hotkey: GlobalHotkey
    var onIconChanged: () -> Void
    var onWindowModeChanged: () -> Void
    var onDockIconChanged: () -> Void

    @State private var pane: SettingsPane? = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    static let size = NSSize(width: 760, height: 560)

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                sidebarRow(.general)
                Section("Features") {
                    ForEach([SettingsPane.camera, .snaps, .vlogs, .floatingWindow, .notch, .micCheck]) { sidebarRow($0) }
                }
                Section { sidebarRow(.about) }
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            Form { detail(pane ?? .general) }
                .formStyle(.grouped)
                .navigationTitle((pane ?? .general).title)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .onAppear {
            camera.refreshDevices()
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func sidebarRow(_ p: SettingsPane) -> some View {
        Label(p.title, systemImage: p.symbol).tag(p)
    }

    @ViewBuilder private func detail(_ p: SettingsPane) -> some View {
        switch p {
        case .general: general
        case .camera: cameraPane
        case .snaps: snaps
        case .vlogs: vlogs
        case .floatingWindow: floatingWindow
        case .notch: notch
        case .micCheck: micCheck
        case .about: about
        }
    }

    // MARK: - General

    @ViewBuilder private var general: some View {
        Section("Appearance") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Menu bar icon")
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(64), spacing: 12), count: 4),
                          alignment: .leading, spacing: 12) {
                    ForEach(MenuBarIcon.allCases, id: \.self) { iconTile($0) }
                }
            }
            Toggle(isOn: binding(\.showDockIcon, then: onDockIconChanged)) {
                Text("Show Dock icon")
                Text("Compact normally lives only in the menu bar.")
            }
        }
        Section("General") {
            LabeledContent("Keyboard shortcut") { ShortcutRecorderView(hotkey: binding(\.hotkey)) }
            if hotkey.registrationFailed, store.settings.hotkey != nil {
                Text("That shortcut is already used by another app. Try a different one.")
                    .font(.caption).foregroundStyle(.red)
            }
            Picker("Popover size", selection: binding(\.popoverSize)) {
                ForEach(WindowSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Toggle(isOn: binding(\.mirrorPreview)) {
                Text("Flip image")
                Text("Like a real mirror. Snaps and vlogs are saved the same way.")
            }
            Picker("Close popover when…", selection: binding(\.closeOnClickOutside)) {
                Text("Clicking outside").tag(true)
                Text("Clicking the menu bar icon").tag(false)
            }
            Toggle(isOn: binding(\.alwaysShowControls)) {
                Text("Always show buttons")
                Text("Otherwise they appear when you point at the video.")
            }
        }
        Section {
            Toggle("Start at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func iconTile(_ icon: MenuBarIcon) -> some View {
        let selected = store.settings.menuBarIcon == icon
        return Button {
            store.update { $0.menuBarIcon = icon }
            onIconChanged()
        } label: {
            Image(nsImage: icon.image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .frame(width: 64, height: 54)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
        .help(icon.displayName)
        .accessibilityLabel(icon.displayName)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: - Camera

    @ViewBuilder private var cameraPane: some View {
        Section {
            Picker("Camera", selection: Binding(
                get: { store.settings.cameraID ?? AVDefault.camera(camera) },
                set: { camera.selectCamera(id: $0) })) {
                ForEach(camera.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
            }
            .disabled(recorder.state.isActive)
            if recorder.state.isActive {
                Text("Can't change while recording").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Show Compact as", selection: binding(\.windowMode, then: onWindowModeChanged)) {
                Text("Popover under the menu bar").tag(WindowMode.popover)
                Text("Floating window").tag(WindowMode.floating)
            }
        }
        Section("Permission") {
            permissionRow("Camera", status: AVCaptureDevice.authorizationStatus(for: .video), privacyPane: "Privacy_Camera")
            permissionRow("Microphone", status: AVCaptureDevice.authorizationStatus(for: .audio), privacyPane: "Privacy_Microphone")
        }
    }

    private func permissionRow(_ name: String, status: AVAuthorizationStatus, privacyPane: String) -> some View {
        LabeledContent(name) {
            HStack(spacing: 8) {
                switch status {
                case .authorized: Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .notDetermined: Text("Not asked yet").foregroundStyle(.secondary)
                default: Label("Off", systemImage: "xmark.circle.fill").foregroundStyle(.red)
                }
                if status == .denied || status == .restricted {
                    Button("Open System Settings") { openPrivacy(privacyPane) }
                }
            }
        }
    }

    // MARK: - Snaps

    @ViewBuilder private var snaps: some View {
        Section {
            Picker("Start with frame", selection: binding(\.defaultSnapFrame)) {
                ForEach(SnapFrame.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle(isOn: binding(\.snapIncludesDate)) {
                Text("Write the date on Polaroid frames")
            }
            Toggle("Shutter sound", isOn: binding(\.snapShutterSound))
        }
        Section("Saving") {
            folderRow(.snap, label: "Pictures → Compact")
            Text("Press Space or the shutter button to take a snap. Save keeps it; clicking anywhere else throws it away.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Vlogs

    @ViewBuilder private var vlogs: some View {
        Section("Saving") {
            folderRow(.vlog, label: "Movies → Compact")
        }
        Section {
            Text("Vlogs record your camera and microphone. Recording keeps going if you close Compact; the menu bar icon turns red until you press stop. Quitting finishes saving first.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func folderRow(_ kind: MediaKind, label: String) -> some View {
        LabeledContent("Saved to") {
            HStack(spacing: 8) {
                Text(label).foregroundStyle(.secondary)
                Button("Open") {
                    let folder = MediaLocation.folder(for: kind, home: FileManager.default.homeDirectoryForCurrentUser)
                    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    NSWorkspace.shared.open(folder)
                }
            }
        }
    }

    // MARK: - Floating window

    @ViewBuilder private var floatingWindow: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.settings.windowMode == .floating },
                set: { on in store.update { $0.windowMode = on ? .floating : .popover }; onWindowModeChanged() })) {
                Text("Use a floating window")
                Text("Stays on top of other windows. Drag it anywhere.")
            }
        }
        Section("Look") {
            Picker("Shape", selection: binding(\.shape)) {
                ForEach(WindowShape.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Size", selection: binding(\.size)) {
                ForEach(WindowSize.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }
            Picker("Opens at", selection: binding(\.position)) {
                ForEach(WindowPosition.allCases, id: \.self) { Text(Self.positionName($0)).tag($0) }
            }
        }
        .disabled(store.settings.windowMode != .floating)
    }

    // MARK: - Notch

    @ViewBuilder private var notch: some View {
        let hasNotch = NotchTriggerController.hasNotch
        Section {
            Toggle(isOn: binding(\.notchTriggerEnabled)) {
                Text("Click the notch to open Compact")
                Text("Click the black area around your Mac's camera to open or close Compact.")
            }
            .disabled(!hasNotch)
            if !hasNotch {
                Text("This Mac's display has no notch.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Mic check

    @ViewBuilder private var micCheck: some View {
        Section {
            Toggle(isOn: Binding(get: { camera.micMeterOn || store.settings.showMicMeter },
                                 set: { camera.setMicMeter(enabled: $0) })) {
                Text("Show the mic meter")
                Text("A level bar over the video that moves when you talk.")
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
        }
    }

    // MARK: - About

    @ViewBuilder private var about: some View {
        Section {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().frame(width: 96, height: 96)
                Text("Compact").font(.title.bold())
                Text("Version \(Self.version)").foregroundStyle(.secondary)
                Text("A free little mirror in your menu bar: check yourself before a call, take snaps, and record quick vlogs.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - Helpers

    private func binding<T>(_ kp: WritableKeyPath<CompactCore.Settings, T>, then: (() -> Void)? = nil) -> Binding<T> {
        Binding(get: { store.settings[keyPath: kp] },
                set: { v in store.update { $0[keyPath: kp] = v }; then?() })
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription). Move Compact to your Applications folder first."
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
        case .remembered: "Where I left it"
        }
    }
}

private enum AVDefault {
    @MainActor static func camera(_ c: CameraController) -> String {
        AVCaptureDevice.default(for: .video)?.uniqueID ?? c.cameras.first?.uniqueID ?? ""
    }
    @MainActor static func microphone(_ c: CameraController) -> String {
        AVCaptureDevice.default(for: .audio)?.uniqueID ?? c.microphones.first?.uniqueID ?? ""
    }
}
