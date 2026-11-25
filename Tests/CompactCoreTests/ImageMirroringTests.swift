import CoreGraphics
import Testing
@testable import CompactCore

@Suite struct ImageMirroringTests {
    /// Builds a width×1 RGBA image from one (r, g, b) triple per pixel.
    private func image(_ pixels: [(UInt8, UInt8, UInt8)]) -> CGImage {
        var bytes: [UInt8] = pixels.flatMap { [$0.0, $0.1, $0.2, 255] }
        let ctx = CGContext(data: &bytes, width: pixels.count, height: 1, bitsPerComponent: 8,
                            bytesPerRow: pixels.count * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// Reads the image back as (r, g, b) per pixel, left to right.
    private func pixels(_ img: CGImage) -> [(UInt8, UInt8, UInt8)] {
        var bytes = [UInt8](repeating: 0, count: img.width * 4)
        let ctx = CGContext(data: &bytes, width: img.width, height: 1, bitsPerComponent: 8,
                            bytesPerRow: img.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: img.width, height: 1))
        return stride(from: 0, to: bytes.count, by: 4).map { (bytes[$0], bytes[$0 + 1], bytes[$0 + 2]) }
    }

    @Test func flipsLeftAndRight() {
        let red: (UInt8, UInt8, UInt8) = (255, 0, 0), green: (UInt8, UInt8, UInt8) = (0, 255, 0), blue: (UInt8, UInt8, UInt8) = (0, 0, 255)
        let flipped = mirroredHorizontally(image([red, green, blue]))
        #expect(flipped != nil)
        let out = pixels(flipped!)
        #expect(out.count == 3)
        #expect(out[0] == blue && out[1] == green && out[2] == red)
    }

    @Test func keepsSize() {
        let img = image([(1, 2, 3), (4, 5, 6)])
        let flipped = mirroredHorizontally(img)!
        #expect(flipped.width == 2 && flipped.height == 1)
    }
}
