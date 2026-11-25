import Testing
import CoreGraphics
@testable import CompactCore

struct NotchGeometryTests {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: 0, y: 950, width: 654, height: 32)
    let right = CGRect(x: 858, y: 950, width: 654, height: 32)

    @Test func notchRectComputed() {
        #expect(notchRect(screenFrame: screen, leftArea: left, rightArea: right)
                == CGRect(x: 654, y: 950, width: 204, height: 32))
    }

    @Test func notchRectNilWithoutAuxAreas() {
        #expect(notchRect(screenFrame: screen, leftArea: nil, rightArea: right) == nil)
        #expect(notchRect(screenFrame: screen, leftArea: left, rightArea: nil) == nil)
        #expect(notchRect(screenFrame: screen, leftArea: nil, rightArea: nil) == nil)
    }

    @Test func notchRectNilWhenOverlapping() {
        let overlapping = CGRect(x: 600, y: 950, width: 654, height: 32)
        #expect(notchRect(screenFrame: screen, leftArea: left, rightArea: overlapping) == nil)
        let touching = CGRect(x: 654, y: 950, width: 600, height: 32)
        #expect(notchRect(screenFrame: screen, leftArea: left, rightArea: touching) == nil)
    }
}
