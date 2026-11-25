import AppKit
import Carbon.HIToolbox
import SwiftUI
import CompactCore

private func hotKeyHandler(_: EventHandlerCallRef?, _ event: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus {
    DispatchQueue.main.async { GlobalHotkey.shared?.fire() }
    return noErr
}

/// Registers one system-wide hotkey via Carbon. The event handler is installed once.
@MainActor
final class GlobalHotkey {
    static weak var shared: GlobalHotkey?

    private var ref: EventHotKeyRef?
    private var handlerInstalled = false
    private var action: (() -> Void)?

    init() { Self.shared = self }

    func register(_ hotkey: Hotkey?, action: @escaping () -> Void) {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        self.action = action
        guard let hotkey else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), hotKeyHandler, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: 0x434D5043 /* 'CMPC' */, id: 1)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        if status == noErr { ref = newRef }
    }

    fileprivate func fire() { action?() }
}

/// "Record Shortcut" button: captures the next key-down with a modifier. Esc cancels; × clears.
struct ShortcutRecorderView: View {
    @Binding var hotkey: Hotkey?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(recording ? "Press shortcut…" : (hotkey?.displayString ?? "Record Shortcut")) {
                recording ? stop() : start()
            }
            if hotkey != nil, !recording {
                Button { hotkey = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .help("Clear shortcut")
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) { stop(); return nil }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var mods: UInt32 = 0
            if flags.contains(.command) { mods |= Hotkey.command }
            if flags.contains(.option) { mods |= Hotkey.option }
            if flags.contains(.control) { mods |= Hotkey.control }
            if flags.contains(.shift) { mods |= Hotkey.shift }
            guard mods != 0 else { return nil }  // need at least one modifier; swallow the key
            hotkey = Hotkey(keyCode: UInt32(event.keyCode), modifiers: mods)
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
