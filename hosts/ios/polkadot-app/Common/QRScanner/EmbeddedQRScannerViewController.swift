import UIKit

/// Hosted as a child of the tab bar panel rather than presented, so it drops the framed
/// full-screen chrome. The layout still carries the message label, so presenter messages use
/// the inherited presentation.
final class EmbeddedQRScannerViewController: QRScannerViewController {
    override func loadView() {
        view = EmbeddedQRScannerViewLayout()
    }
}
