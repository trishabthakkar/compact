import Testing
@testable import CompactCore

@Suite struct SnapFrameTests {
    @Test func noFrameComesFirstAndIsTheDefault() {
        #expect(SnapFrame.allCases.first == SnapFrame.none)
        #expect(SnapFrame.default == SnapFrame.none)
    }

    @Test func choicesAndNames() {
        #expect(SnapFrame.allCases == [.none, .polaroid, .white, .black, .film])
        #expect(SnapFrame.allCases.map(\.displayName) == ["None", "Polaroid", "White", "Black", "Film"])
    }

    @Test func onlyPolaroidShowsTheDate() {
        #expect(SnapFrame.allCases.filter(\.showsDate) == [.polaroid])
    }
}
