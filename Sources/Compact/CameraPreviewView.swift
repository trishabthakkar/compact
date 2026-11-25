import AVFoundation
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ view: PreviewNSView, context: Context) {}

    final class PreviewNSView: NSView {
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
        }
        required init?(coder: NSCoder) { fatalError("unused") }
        override func makeBackingLayer() -> CALayer { AVCaptureVideoPreviewLayer() }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
