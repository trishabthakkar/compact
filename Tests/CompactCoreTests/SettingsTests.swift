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
        #expect(MenuBarIcon.allCases.count == 5)
    }
}
