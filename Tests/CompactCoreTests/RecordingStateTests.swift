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

@Suite struct RecordingOutcomeTests {
    @Test func cleanFinishIsSaved() {
        #expect(RecordingOutcome(errorMessage: nil, fileFinishedOK: true, fileExists: true) == .saved)
    }
    @Test func errorButFileFinishedIsSavedEarly() {
        #expect(RecordingOutcome(errorMessage: "Disk full", fileFinishedOK: true, fileExists: true)
                == .stoppedEarly(reason: "Disk full"))
    }
    @Test func errorAndBrokenFileFails() {
        #expect(RecordingOutcome(errorMessage: "Device gone", fileFinishedOK: false, fileExists: true)
                == .failed(reason: "Device gone"))
    }
    @Test func errorAndNoFileFails() {
        #expect(RecordingOutcome(errorMessage: "No permission", fileFinishedOK: false, fileExists: false)
                == .failed(reason: "No permission"))
    }
    @Test func stoppedBeforeAnythingWasWritten() {
        #expect(RecordingOutcome(errorMessage: nil, fileFinishedOK: true, fileExists: false) == .nothingRecorded)
    }
}
