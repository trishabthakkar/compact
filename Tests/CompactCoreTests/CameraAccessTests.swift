import AVFoundation
import Testing
@testable import CompactCore

struct CameraAccessTests {
    @Test func mapsStatuses() {
        #expect(CameraAccess.from(status: .authorized, hasDevice: true) == .allowed)
        #expect(CameraAccess.from(status: .notDetermined, hasDevice: true) == .notDetermined)
        #expect(CameraAccess.from(status: .denied, hasDevice: true) == .denied)
        #expect(CameraAccess.from(status: .restricted, hasDevice: true) == .denied)
    }

    @Test func noDeviceWins() {
        #expect(CameraAccess.from(status: .authorized, hasDevice: false) == .noCamera)
    }

    @Test func deniedHasMessage() {
        #expect(CameraAccess.denied.message?.contains("System Settings") == true)
        #expect(CameraAccess.allowed.message == nil)
    }

    @Test func shouldRunCameraTable() {
        #expect(shouldRunCamera(panelVisible: false, isRecording: false) == false)
        #expect(shouldRunCamera(panelVisible: true, isRecording: false) == true)
        #expect(shouldRunCamera(panelVisible: false, isRecording: true) == true)
        #expect(shouldRunCamera(panelVisible: true, isRecording: true) == true)
    }

    @Test func screenUnavailableStopsCameraUnlessRecording() {
        #expect(shouldRunCamera(panelVisible: true, isRecording: false, screenAvailable: false) == false)
        #expect(shouldRunCamera(panelVisible: true, isRecording: true, screenAvailable: false) == true)
        #expect(shouldRunCamera(panelVisible: false, isRecording: false, screenAvailable: false) == false)
        #expect(shouldRunCamera(panelVisible: true, isRecording: false, screenAvailable: true) == true)
    }
}

@Suite struct PanelKeepOpenTests {
    @Test func outsideClicksCloseOnlyWhenNothingIsInProgress() {
        #expect(outsideClickCloses(isRecording: false, hasUnsavedSnap: false) == true)
        #expect(outsideClickCloses(isRecording: true, hasUnsavedSnap: false) == false)
        #expect(outsideClickCloses(isRecording: false, hasUnsavedSnap: true) == false)
        #expect(outsideClickCloses(isRecording: true, hasUnsavedSnap: true) == false)
    }

    @Test func onlyAnUnsavedSnapBlocksDeliberateClosing() {
        // The menu bar icon / hotkey / × still close during a recording (it keeps recording),
        // but not while a snap is unsaved, since closing would throw the snap away.
        #expect(deliberateCloseAllowed(hasUnsavedSnap: false) == true)
        #expect(deliberateCloseAllowed(hasUnsavedSnap: true) == false)
    }
}
