import CoreGraphics

/// Returns a left-right mirrored copy of `image`, same size. Used so a snap looks
/// exactly like the mirrored live preview.
public func mirroredHorizontally(_ image: CGImage) -> CGImage? {
    let width = image.width, height = image.height
    guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.translateBy(x: CGFloat(width), y: 0)
    ctx.scaleBy(x: -1, y: 1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()
}
