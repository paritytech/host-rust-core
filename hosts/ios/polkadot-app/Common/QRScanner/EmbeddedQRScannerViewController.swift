import AVFoundation
import UIKit

/// What the scan panel needs from its scanner: the two states are independent — the preview
/// stays live while recognition is disarmed.
protocol ScanPanelScannerControlling: AnyObject {
    func setRecognitionArmed(_ armed: Bool)
    func setPreviewCompact(_ compact: Bool)
}

/// Hosted as a child of the tab bar panel rather than presented, so it drops the framed
/// full-screen chrome. The layout still carries the message label, so presenter messages use
/// the inherited presentation.
final class EmbeddedQRScannerViewController: QRScannerViewController, ScanPanelScannerControlling {
    override func loadView() {
        view = EmbeddedQRScannerViewLayout()
    }

    /// The embedded preview lives in `CameraPreviewView`, not in the frame view's bare layer.
    override func configureVideoLayer(with captureSession: AVCaptureSession) {
        guard let layout = view as? EmbeddedQRScannerViewLayout,
              let previewLayer = layout.previewView.previewLayer else {
            return
        }

        if previewLayer.session !== captureSession {
            previewLayer.session = captureSession
        }

        layout.didAttachPreview()
    }

    func setRecognitionArmed(_ armed: Bool) {
        presenter.setRecognitionArmed(armed)
    }

    func setPreviewCompact(_ compact: Bool) {
        (view as? EmbeddedQRScannerViewLayout)?.setPreviewCompact(compact)
    }
}
