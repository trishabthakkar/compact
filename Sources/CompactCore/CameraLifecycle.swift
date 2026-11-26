
/// The camera runs only while the panel is visible on an available (awake, unlocked) screen, or while recording.
public func shouldRunCamera(panelVisible: Bool, isRecording: Bool, screenAvailable: Bool = true) -> Bool {
    (panelVisible && screenAvailable) || isRecording
}

/// Clicking outside Compact closes the camera view only when nothing is in progress:
/// not while recording, and not while a snap is waiting to be saved or discarded.
public func outsideClickCloses(isRecording: Bool, hasUnsavedSnap: Bool) -> Bool {
    !isRecording && !hasUnsavedSnap
}

/// Closing on purpose (menu bar icon, shortcut, ×) is allowed during a recording, which keeps
/// going, but not while a snap is unsaved, because closing would throw the snap away.
public func deliberateCloseAllowed(hasUnsavedSnap: Bool) -> Bool {
    !hasUnsavedSnap
}
