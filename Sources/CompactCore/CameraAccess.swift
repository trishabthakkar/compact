import AVFoundation

public enum CameraAccess: Equatable, Sendable {
    case allowed, notDetermined, denied, noCamera

    public static func from(status: AVAuthorizationStatus, hasDevice: Bool) -> CameraAccess {
        guard hasDevice else { return .noCamera }
        switch status {
        case .authorized: return .allowed
        case .notDetermined: return .notDetermined
        case .denied, .restricted: return .denied
        @unknown default: return .denied
        }
    }

    public var message: String? {
        switch self {
        case .denied:
            "Compact can't see your camera. Turn it on in System Settings → Privacy & Security → Camera."
        case .noCamera:
            "No camera found. Plug one in or close the app that's using it."
        case .allowed, .notDetermined:
            nil
        }
    }
}
