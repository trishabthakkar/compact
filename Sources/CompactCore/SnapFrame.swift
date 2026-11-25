/// Optional frames you can add to a snap after taking it. A snap starts with no frame.
public enum SnapFrame: String, CaseIterable, Sendable {
    case none, polaroid, white, black, film

    public static let `default`: SnapFrame = .none

    public var displayName: String {
        switch self {
        case .none: "None"
        case .polaroid: "Polaroid"
        case .white: "White"
        case .black: "Black"
        case .film: "Film"
        }
    }

    /// Only the Polaroid frame has room for a handwritten date.
    public var showsDate: Bool { self == .polaroid }
}
