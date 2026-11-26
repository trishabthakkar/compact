import Foundation

public enum RecordingState: Equatable, Sendable {
    case idle
    case recording(startedAt: Date, url: URL)
    case stopping
    case failed(message: String)

    /// True while a recording is in progress or being finalized.
    public var isActive: Bool {
        switch self {
        case .recording, .stopping: true
        case .idle, .failed: false
        }
    }
}

/// `m:ss` under an hour, otherwise `h:mm:ss`.
public func elapsedLabel(from start: Date, to now: Date) -> String {
    let total = max(0, Int(now.timeIntervalSince(start)))
    let h = total / 3600, m = (total % 3600) / 60, s = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// What to tell the user once a recording has ended.
public enum RecordingOutcome: Equatable, Sendable {
    /// The whole video was saved.
    case saved
    /// Recording stopped by itself (e.g. disk full), but what was recorded was saved.
    case stoppedEarly(reason: String)
    /// The video couldn't be saved.
    case failed(reason: String)
    /// Stopped before anything was written (e.g. stop pressed straight after record).
    case nothingRecorded

    public init(errorMessage: String?, fileFinishedOK: Bool, fileExists: Bool) {
        switch (errorMessage, fileFinishedOK, fileExists) {
        case (nil, _, true): self = .saved
        case (nil, _, false): self = .nothingRecorded
        case (let reason?, true, true): self = .stoppedEarly(reason: reason)
        case (let reason?, _, _): self = .failed(reason: reason)
        }
    }
}
