import CoreGraphics

/// The camera housing rect between the two menu-bar areas beside the notch, or nil if there is no notch.
public func notchRect(screenFrame: CGRect, leftArea: CGRect?, rightArea: CGRect?) -> CGRect? {
    guard let leftArea, let rightArea, rightArea.minX > leftArea.maxX else { return nil }
    return CGRect(x: leftArea.maxX,
                  y: min(leftArea.minY, rightArea.minY),
                  width: rightArea.minX - leftArea.maxX,
                  height: max(leftArea.height, rightArea.height))
}
