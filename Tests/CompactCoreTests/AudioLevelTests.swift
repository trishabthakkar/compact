import Testing
@testable import CompactCore

@Suite struct AudioLevelTests {
    @Test(arguments: [
        (Float(-60), 0.0), (Float(0), 1.0), (Float(-30), 0.5),
        (Float(-100), 0.0), (Float(3), 1.0), (Float(-160), 0.0),
    ])
    func normalizes(db: Float, expected: Double) {
        #expect(abs(normalizedLevel(decibels: db) - expected) < 0.0001)
    }
}
