
/// The camera runs only while the panel is visible on an available (awake, unlocked) screen, or while recording.
public func shouldRunCamera(panelVisible: Bool, isRecording: Bool, screenAvailable: Bool = true) -> Bool {
    (panelVisible && screenAvailable) || isRecording
}

/// Clicking outside Compact closes the camera view, except while recording.
public func outsideClickCloses(isRecording: Bool) -> Bool {
    !isRecording
}
