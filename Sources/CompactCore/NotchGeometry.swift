import CoreGraphics

/// The camera housing rect (global coordinates) between the two menu-bar areas beside the notch,
/// or nil if there is no notch. `NSScreen.auxiliaryTop*Area` are reported in the screen's own
/// coordinate space (origin at the screen's bottom-left), so they are offset by `screenFrame.origin`.
/// A rect that doesn't land inside `screenFrame` is rejected.
public func notchRect(screenFrame: CGRect, leftArea: CGRect?, rightArea: CGRect?) -> CGRect? {
    guard let leftArea, let rightArea, rightArea.minX > leftArea.maxX else { return nil }
    let rect = CGRect(x: screenFrame.minX + leftArea.maxX,
                      y: screenFrame.minY + min(leftArea.minY, rightArea.minY),
                      width: rightArea.minX - leftArea.maxX,
                      height: max(leftArea.height, rightArea.height))
    return screenFrame.contains(rect) ? rect : nil
}
