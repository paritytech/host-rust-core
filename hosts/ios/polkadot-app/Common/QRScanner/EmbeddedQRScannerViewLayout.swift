import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

/// Bare camera preview that fills its host's bounds: no dimmed cutout and no frame border, with
/// the message label drawn straight over the preview. `fillColor` is what draws the dimming in
/// `CameraFrameView`, so clearing it removes the window entirely. The host view (`ScanPanelViewLayout`)
/// owns the insets and placeholder.
final class EmbeddedQRScannerViewLayout: QRScannerViewLayout {
    private enum Constants {
        static let previewFadeDuration: TimeInterval = 0.25
    }

    let previewView = CameraPreviewView()

    override func setupLayout() {
        backgroundColor = .clear

        heightAnchor.constraint(equalTo: widthAnchor).isActive = true

        addSubview(qrFrameView)
        qrFrameView.alpha = 0
        qrFrameView.layer.cornerRadius = DSRadii.large
        qrFrameView.layer.masksToBounds = true
        qrFrameView.fillColor = .clear
        qrFrameView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        qrFrameView.addSubview(previewView)
        previewView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        messageLabel.textColor = .fgPrimary
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.leading.trailing.equalTo(qrFrameView).inset(DSSpacings.mediumIncreased)
            make.bottom.equalTo(qrFrameView).inset(DSSpacings.mediumIncreased)
        }
    }

    override func didAttachPreview() {
        UIView.animate(withDuration: Constants.previewFadeDuration) { [self] in
            qrFrameView.alpha = 1
        }
    }

    /// Hides the overlay message while the preview is a thumbnail. The reticle, title and dimming
    /// cut-out are already absent from this layout, so nothing else needs suppressing.
    func setPreviewCompact(_ compact: Bool) {
        messageLabel.isHidden = compact
    }
}
