import CompactCore
import AppKit

/// Hand-drawn menu bar icons for the shapes SF Symbols doesn't have: a makeup compact, a lipstick
/// and a bow. Drawn as 18×18 pt template images, so macOS tints them for light/dark menu bars.
enum MenuBarIconArt {
    static let size = NSSize(width: 18, height: 18)

    /// An open round compact: rim, mirror and a diagonal glint (like the app icon).
    static func compact() -> NSImage {
        image { _ in
            let center = NSPoint(x: 9, y: 9)
            let rim = NSBezierPath(ovalIn: NSRect(x: 1.6, y: 1.6, width: 14.8, height: 14.8))
            rim.lineWidth = 1.7
            rim.stroke()
            // Mirror with the glint cut out (even-odd fill leaves the glint clear).
            let mirror = NSBezierPath(ovalIn: NSRect(x: center.x - 4.9, y: center.y - 4.9, width: 9.8, height: 9.8))
            let glint = NSBezierPath()
            glint.move(to: NSPoint(x: 5.6, y: 9.6))
            glint.line(to: NSPoint(x: 9.6, y: 13.6))
            glint.line(to: NSPoint(x: 11.0, y: 12.2))
            glint.line(to: NSPoint(x: 7.0, y: 8.2))
            glint.close()
            mirror.append(glint)
            mirror.windingRule = .evenOdd
            mirror.fill()
        }
    }

    /// A lipstick: tube, collar and a slanted bullet.
    static func lipstick() -> NSImage {
        image { _ in
            NSBezierPath(roundedRect: NSRect(x: 5.2, y: 1.0, width: 7.6, height: 7.0), xRadius: 1.2, yRadius: 1.2).fill()
            NSBezierPath(rect: NSRect(x: 6.2, y: 8.7, width: 5.6, height: 2.2)).fill()
            let bullet = NSBezierPath()
            bullet.move(to: NSPoint(x: 6.8, y: 11.6))
            bullet.line(to: NSPoint(x: 6.8, y: 14.6))
            bullet.curve(to: NSPoint(x: 11.2, y: 17.2),
                         controlPoint1: NSPoint(x: 6.8, y: 15.8), controlPoint2: NSPoint(x: 9.6, y: 17.2))
            bullet.line(to: NSPoint(x: 11.2, y: 11.6))
            bullet.close()
            bullet.fill()
        }
    }

    /// A bow: two loops, a knot and two short tails.
    static func bow() -> NSImage {
        image { _ in
            for side: CGFloat in [-1, 1] {
                let loop = NSBezierPath()
                loop.move(to: NSPoint(x: 9, y: 10))
                loop.curve(to: NSPoint(x: 9 + side * 7.6, y: 13.6),
                           controlPoint1: NSPoint(x: 9 + side * 3.0, y: 13.2), controlPoint2: NSPoint(x: 9 + side * 5.2, y: 15.8))
                loop.curve(to: NSPoint(x: 9 + side * 7.2, y: 6.4),
                           controlPoint1: NSPoint(x: 9 + side * 9.4, y: 11.8), controlPoint2: NSPoint(x: 9 + side * 9.2, y: 7.6))
                loop.curve(to: NSPoint(x: 9, y: 8.6),
                           controlPoint1: NSPoint(x: 9 + side * 5.0, y: 5.4), controlPoint2: NSPoint(x: 9 + side * 2.6, y: 7.0))
                loop.close()
                loop.fill()
                let tail = NSBezierPath()
                tail.move(to: NSPoint(x: 9 + side * 0.8, y: 8.2))
                tail.line(to: NSPoint(x: 9 + side * 3.8, y: 1.8))
                tail.lineWidth = 1.8
                tail.lineCapStyle = .round
                tail.stroke()
            }
            NSBezierPath(roundedRect: NSRect(x: 7.3, y: 7.4, width: 3.4, height: 3.8), xRadius: 1.2, yRadius: 1.2).fill()
        }
    }

    private static func image(_ draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension MenuBarIcon {
    /// The menu bar image for this choice: an SF Symbol, or Compact's own drawing.
    var image: NSImage {
        switch self {
        case .compact: return MenuBarIconArt.compact()
        case .lipstick: return MenuBarIconArt.lipstick()
        case .bow: return MenuBarIconArt.bow()
        default:
            let image = NSImage(systemSymbolName: symbolName ?? "camera.fill", accessibilityDescription: displayName)
                ?? MenuBarIconArt.compact()
            image.isTemplate = true
            return image
        }
    }
}
