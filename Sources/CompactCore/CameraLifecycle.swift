/// The camera runs only while the panel is visible or a recording is in progress.
public func shouldRunCamera(panelVisible: Bool, isRecording: Bool) -> Bool {
    panelVisible || isRecording
}
