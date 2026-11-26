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
    @Test func outsideClicksCloseUnlessRecording() {
        #expect(outsideClickCloses(isRecording: false) == true)
        #expect(outsideClickCloses(isRecording: true) == false)
    }
}
