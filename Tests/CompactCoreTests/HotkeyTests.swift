import Testing
import Foundation
@testable import CompactCore

@MainActor
struct HotkeyTests {
    @Test func hotkeyDisplay() {
        let mods = Hotkey.control | Hotkey.option | Hotkey.command
        #expect(Hotkey(keyCode: 35, modifiers: mods).displayString == "⌃⌥⌘P")
        #expect(Hotkey(keyCode: 49, modifiers: Hotkey.shift | Hotkey.command).displayString == "⇧⌘Space")
    }

    @Test func hotkeyPersists() {
        let d = UserDefaults(suiteName: "test.\(UUID())")!
        let store = SettingsStore(defaults: d)
        #expect(store.settings.hotkey == nil)
        store.update { $0.hotkey = Hotkey(keyCode: 35, modifiers: 6400) }
        #expect(SettingsStore(defaults: d).settings.hotkey == Hotkey(keyCode: 35, modifiers: 6400))
        store.update { $0.hotkey = nil }
        #expect(SettingsStore(defaults: d).settings.hotkey == nil)
        d.set([1], forKey: "compact.hotkey")
        #expect(SettingsStore(defaults: d).settings.hotkey == nil)
    }
}
