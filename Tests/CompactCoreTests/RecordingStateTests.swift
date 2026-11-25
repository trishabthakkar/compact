import Testing
import Foundation
@testable import CompactCore

@Suite struct RecordingStateTests {
    @Test func isActive() {
        let url = URL(fileURLWithPath: "/tmp/x.mov")
        #expect(!RecordingState.idle.isActive)
        #expect(RecordingState.recording(startedAt: Date(), url: url).isActive)
        #expect(RecordingState.stopping.isActive)
        #expect(!RecordingState.failed(message: "x").isActive)
    }

    @Test(arguments: [(7.0, "0:07"), (65.0, "1:05"), (3909.0, "1:05:09"), (0.0, "0:00"), (-5.0, "0:00")])
    func elapsed(seconds: Double, expected: String) {
        let start = Date(timeIntervalSince1970: 1000)
        #expect(elapsedLabel(from: start, to: start.addingTimeInterval(seconds)) == expected)
    }
}
