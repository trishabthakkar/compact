import Foundation
import CoreGraphics
import Observation

public enum WindowMode: String, CaseIterable, Sendable { case popover, floating }
public enum WindowShape: String, CaseIterable, Sendable { case rounded, square, circle, capsule }
public enum WindowSize: String, CaseIterable, Sendable { case small, medium, large }
public enum WindowPosition: String, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight, center, remembered
}

public enum MenuBarIcon: String, CaseIterable, Sendable {
    case camera, smile, dot, sparkles, eye

    public var symbolName: String {
        switch self {
        case .camera: "camera.fill"
        case .smile: "face.smiling"
        case .dot: "circle.inset.filled"
        case .sparkles: "sparkles"
        case .eye: "eye"
        }
    }
}

public struct Settings: Equatable, Sendable {
    public var windowMode: WindowMode = .popover
    public var shape: WindowShape = .rounded
    public var size: WindowSize = .medium
    public var position: WindowPosition = .topRight
    public var menuBarIcon: MenuBarIcon = .camera
    public var mirrorPreview: Bool = true
    public var showMicMeter: Bool = false
    public var snapIncludesDate: Bool = true
    public var notchTriggerEnabled: Bool = false
    public var rememberedOrigin: CGPoint? = nil
    public var cameraID: String? = nil
    public var microphoneID: String? = nil

    public init() {}
}

@MainActor @Observable
public final class SettingsStore {
    public private(set) var settings: Settings
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults)
    }

    public func update(_ change: (inout Settings) -> Void) {
        var new = settings
        change(&new)
        settings = new
        save(new)
    }

    private static func key(_ name: String) -> String { "compact.\(name)" }

    private static func load(from d: UserDefaults) -> Settings {
        var s = Settings()
        func raw<T: RawRepresentable>(_ name: String, _ fallback: T) -> T where T.RawValue == String {
            d.string(forKey: key(name)).flatMap(T.init(rawValue:)) ?? fallback
        }
        func bool(_ name: String, _ fallback: Bool) -> Bool {
            d.object(forKey: key(name)) as? Bool ?? fallback
        }
        s.windowMode = raw("windowMode", s.windowMode)
        s.shape = raw("shape", s.shape)
        s.size = raw("size", s.size)
        s.position = raw("position", s.position)
        s.menuBarIcon = raw("menuBarIcon", s.menuBarIcon)
        s.mirrorPreview = bool("mirrorPreview", s.mirrorPreview)
        s.showMicMeter = bool("showMicMeter", s.showMicMeter)
        s.snapIncludesDate = bool("snapIncludesDate", s.snapIncludesDate)
        s.notchTriggerEnabled = bool("notchTriggerEnabled", s.notchTriggerEnabled)
        if let xy = d.array(forKey: key("rememberedOrigin")) as? [Double], xy.count == 2 {
            s.rememberedOrigin = CGPoint(x: xy[0], y: xy[1])
        }
        s.cameraID = d.string(forKey: key("cameraID"))
        s.microphoneID = d.string(forKey: key("microphoneID"))
        return s
    }

    private func save(_ s: Settings) {
        func set(_ name: String, _ value: Any?) {
            if let value { defaults.set(value, forKey: Self.key(name)) }
            else { defaults.removeObject(forKey: Self.key(name)) }
        }
        set("windowMode", s.windowMode.rawValue)
        set("shape", s.shape.rawValue)
        set("size", s.size.rawValue)
        set("position", s.position.rawValue)
        set("menuBarIcon", s.menuBarIcon.rawValue)
        set("mirrorPreview", s.mirrorPreview)
        set("showMicMeter", s.showMicMeter)
        set("snapIncludesDate", s.snapIncludesDate)
        set("notchTriggerEnabled", s.notchTriggerEnabled)
        set("rememberedOrigin", s.rememberedOrigin.map { [Double($0.x), Double($0.y)] })
        set("cameraID", s.cameraID)
        set("microphoneID", s.microphoneID)
    }
}
