// Generates the Compact app icon: an open round compact mirror seen from above.
// Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit
import CoreGraphics
import Foundation

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r / 255, g / 255, b / 255, a])!
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: locations)!
}

/// Draws the icon on a 1024-unit canvas; the context is pre-scaled by the caller.
func draw(_ ctx: CGContext) {
    let canvas: CGFloat = 1024
    let margin = canvas * 0.10
    let side = canvas - 2 * margin
    let bg = CGRect(x: margin, y: margin, width: side, height: side)
    let bgPath = CGPath(roundedRect: bg, cornerWidth: side * 0.225, cornerHeight: side * 0.225, transform: nil)

    // Soft drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: rgb(30, 30, 80, 0.22))
    ctx.addPath(bgPath)
    ctx.setFillColor(rgb(150, 160, 230))
    ctx.fillPath()
    ctx.restoreGState()

    // Background: blue (top) to lavender (bottom).
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(120, 170, 245), rgb(190, 160, 235)], [0, 1]),
        start: CGPoint(x: 0, y: bg.maxY), end: CGPoint(x: 0, y: bg.minY), options: [])
    ctx.restoreGState()

    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let outerR = side * 0.375
    let rimW = side * 0.055
    let innerR = outerR - rimW

    // Compact body shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: rgb(40, 30, 100, 0.40))
    ctx.setFillColor(rgb(200, 205, 220))
    ctx.fillEllipse(in: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2))
    ctx.restoreGState()

    // Silver rim.
    ctx.saveGState()
    ctx.addEllipse(in: CGRect(x: center.x - outerR, y: center.y - outerR, width: outerR * 2, height: outerR * 2))
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(252, 252, 255), rgb(176, 182, 200), rgb(232, 235, 245)], [0, 0.55, 1]),
        start: CGPoint(x: center.x - outerR, y: center.y + outerR),
        end: CGPoint(x: center.x + outerR, y: center.y - outerR), options: [])
    ctx.restoreGState()

    // Thin dark ring separating rim from glass.
    let ringR = innerR + side * 0.006
    ctx.setStrokeColor(rgb(120, 128, 160, 0.55))
    ctx.setLineWidth(side * 0.006)
    ctx.strokeEllipse(in: CGRect(x: center.x - ringR, y: center.y - ringR, width: ringR * 2, height: ringR * 2))

    // Mirror glass: light reflective gradient.
    let glass = CGRect(x: center.x - innerR, y: center.y - innerR, width: innerR * 2, height: innerR * 2)
    ctx.saveGState()
    ctx.addEllipse(in: glass)
    ctx.clip()
    ctx.drawLinearGradient(
        gradient([rgb(246, 250, 255), rgb(205, 222, 245), rgb(228, 218, 245)], [0, 0.6, 1]),
        start: CGPoint(x: center.x - innerR * 0.6, y: center.y + innerR),
        end: CGPoint(x: center.x + innerR * 0.6, y: center.y - innerR), options: [])
    // Inner edge shading for depth.
    ctx.drawRadialGradient(
        gradient([rgb(120, 130, 175, 0), rgb(120, 130, 175, 0.28)], [0, 1]),
        startCenter: center, startRadius: innerR * 0.75, endCenter: center, endRadius: innerR, options: [])

    // Diagonal glint: two white bands, lower-left to upper-right.
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: .pi / 4)
    ctx.setFillColor(rgb(255, 255, 255, 0.85))
    ctx.fill(CGRect(x: -innerR, y: innerR * 0.22, width: innerR * 2, height: innerR * 0.20))
    ctx.setFillColor(rgb(255, 255, 255, 0.55))
    ctx.fill(CGRect(x: -innerR, y: innerR * 0.50, width: innerR * 2, height: innerR * 0.07))
    ctx.restoreGState()
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = gctx
    let ctx = gctx.cgContext
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <out.iconset>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in sizes {
    try render(pixels: px).write(to: outDir.appendingPathComponent("\(name).png"))
}
