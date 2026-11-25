import CoreGraphics

public func contentSize(size: WindowSize, shape: WindowShape) -> CGSize {
    let base: CGSize = switch size {
    case .small: CGSize(width: 240, height: 180)
    case .medium: CGSize(width: 320, height: 240)
    case .large: CGSize(width: 480, height: 360)
    }
    return shape == .circle ? CGSize(width: base.width, height: base.width) : base
}

public func cornerRadius(shape: WindowShape, in size: CGSize) -> CGFloat {
    switch shape {
    case .rounded: 16
    case .square: 0
    case .circle, .capsule: min(size.width, size.height) / 2
    }
}

/// AppKit coordinates (origin bottom-left). Result is always clamped inside `visibleFrame`.
public func windowOrigin(position: WindowPosition, windowSize: CGSize, visibleFrame vf: CGRect,
                         remembered: CGPoint?, margin: CGFloat = 20) -> CGPoint {
    let left = vf.minX + margin, right = vf.maxX - windowSize.width - margin
    let bottom = vf.minY + margin, top = vf.maxY - windowSize.height - margin
    var pos = position
    if pos == .remembered {
        if let r = remembered, vf.intersects(CGRect(origin: r, size: windowSize)) {
            return clamp(r, windowSize, vf)
        }
        pos = .topRight
    }
    let raw: CGPoint = switch pos {
    case .topLeft: CGPoint(x: left, y: top)
    case .topRight, .remembered: CGPoint(x: right, y: top)
    case .bottomLeft: CGPoint(x: left, y: bottom)
    case .bottomRight: CGPoint(x: right, y: bottom)
    case .center: CGPoint(x: vf.midX - windowSize.width / 2, y: vf.midY - windowSize.height / 2)
    }
    return clamp(raw, windowSize, vf)
}

private func clamp(_ p: CGPoint, _ size: CGSize, _ vf: CGRect) -> CGPoint {
    CGPoint(x: max(vf.minX, min(p.x, vf.maxX - size.width)),
            y: max(vf.minY, min(p.y, vf.maxY - size.height)))
}
