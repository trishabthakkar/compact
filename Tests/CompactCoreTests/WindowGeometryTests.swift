import Testing
import CoreGraphics
@testable import CompactCore

@Suite struct WindowGeometryTests {
    let vf = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let ws = CGSize(width: 320, height: 240)

    @Test func sizes() {
        #expect(contentSize(size: .medium, shape: .rounded) == CGSize(width: 320, height: 240))
        #expect(contentSize(size: .large, shape: .circle) == CGSize(width: 480, height: 480))
        #expect(contentSize(size: .small, shape: .square) == CGSize(width: 240, height: 180))
    }

    @Test func radii() {
        #expect(cornerRadius(shape: .square, in: CGSize(width: 320, height: 240)) == 0)
        #expect(cornerRadius(shape: .circle, in: CGSize(width: 240, height: 240)) == 120)
        #expect(cornerRadius(shape: .capsule, in: CGSize(width: 320, height: 240)) == 120)
        #expect(cornerRadius(shape: .rounded, in: CGSize(width: 320, height: 240)) == 16)
    }

    @Test func corners() {
        #expect(windowOrigin(position: .topRight, windowSize: ws, visibleFrame: vf, remembered: nil) == CGPoint(x: 1100, y: 615))
        #expect(windowOrigin(position: .bottomLeft, windowSize: ws, visibleFrame: vf, remembered: nil) == CGPoint(x: 20, y: 20))
        #expect(windowOrigin(position: .center, windowSize: ws, visibleFrame: vf, remembered: nil) == CGPoint(x: 560, y: 317.5))
    }

    @Test func rememberedUsedWhenOnScreen() {
        #expect(windowOrigin(position: .remembered, windowSize: ws, visibleFrame: vf, remembered: CGPoint(x: 300, y: 300)) == CGPoint(x: 300, y: 300))
    }

    @Test func rememberedOffScreenFallsBack() {
        #expect(windowOrigin(position: .remembered, windowSize: ws, visibleFrame: vf, remembered: CGPoint(x: 5000, y: 5000)) == CGPoint(x: 1100, y: 615))
        #expect(windowOrigin(position: .remembered, windowSize: ws, visibleFrame: vf, remembered: nil) == CGPoint(x: 1100, y: 615))
    }

    @Test func clampedInsideVisibleFrame() {
        let o = windowOrigin(position: .remembered, windowSize: ws, visibleFrame: vf, remembered: CGPoint(x: 1400, y: 800))
        #expect(o == CGPoint(x: 1120, y: 635))
    }
}
