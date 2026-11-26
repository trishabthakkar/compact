import Testing
import Foundation
import CoreGraphics
@testable import CompactCore

@MainActor
struct SettingsTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID())")!
    }

    @Test func defaultsWhenEmpty() {
        let d = freshDefaults()
        #expect(SettingsStore(defaults: d).settings == Settings())
    }

    @Test func shutterSoundOffByDefaultAndPersists() {
        let d = freshDefaults()
        #expect(SettingsStore(defaults: d).settings.snapShutterSound == false)
        SettingsStore(defaults: d).update { $0.snapShutterSound = true }
        #expect(SettingsStore(defaults: d).settings.snapShutterSound == true)
    }

    @Test func updatePersistsAcrossInstances() {
        let d = freshDefaults()
        let store = SettingsStore(defaults: d)
        store.update {
            $0.shape = .circle
            $0.rememberedOrigin = CGPoint(x: 10, y: 20)
        }
        let reloaded = SettingsStore(defaults: d)
        #expect(reloaded.settings.shape == .circle)
        #expect(reloaded.settings.rememberedOrigin == CGPoint(x: 10, y: 20))
    }

    @Test func garbageValueFallsBack() {
        let d = freshDefaults()
        d.set("hexagon", forKey: "compact.shape")
        #expect(SettingsStore(defaults: d).settings.shape == .rounded)
    }

    @Test func menuBarSymbols() {
        #expect(MenuBarIcon.camera.symbolName == "camera.fill")
        #expect(MenuBarIcon.allCases.count == 8)
        // The compact, lipstick and bow are drawn by Compact itself (no SF Symbol exists).
        #expect(MenuBarIcon.allCases.filter { $0.symbolName == nil } == [.compact, .lipstick, .bow])
        #expect(MenuBarIcon.allCases.map(\.displayName)
                == ["Compact", "Lipstick", "Bow", "Camera", "Smile", "Dot", "Sparkles", "Eye"])
    }

    @Test func newSettingsDefaults() {
        let s = Settings()
        #expect(s.menuBarIcon == .compact)
        #expect(s.popoverSize == .medium)
        #expect(s.showDockIcon == false)
        #expect(s.closeOnClickOutside == true)
        #expect(s.alwaysShowControls == false)
        #expect(s.defaultSnapFrame == SnapFrame.none)
    }

    @Test func newSettingsPersist() {
        let d = freshDefaults()
        SettingsStore(defaults: d).update {
            $0.menuBarIcon = .bow
            $0.popoverSize = .large
            $0.showDockIcon = true
            $0.closeOnClickOutside = false
            $0.alwaysShowControls = true
            $0.defaultSnapFrame = .film
        }
        let s = SettingsStore(defaults: d).settings
        #expect(s.menuBarIcon == .bow && s.popoverSize == .large && s.showDockIcon)
        #expect(!s.closeOnClickOutside && s.alwaysShowControls && s.defaultSnapFrame == .film)
    }
}
