import UIKit
import UIKit_iOS
import PolkadotUI
import DesignSystem

/// Bare camera preview for the tab bar panel: no dimmed cutout and no frame border, with the
/// message label drawn straight over the preview. `fillColor` is what draws the dimming in
/// `CameraFrameView`, so clearing it removes the window entirely and the preview fills the view.
final class EmbeddedQRScannerViewLayout: QRScannerViewLayout {
    private enum Constants {
        static let previewFadeDuration: TimeInterval = 0.25
    }

    /// Stands in for the camera while `AVCaptureSession` configures and starts, which takes
    /// roughly a second and cannot be shortened from here.
    private let placeholderView = UIView()

    override func setupLayout() {
        // The base init paints `bgSurfaceMain`; the panel's glass must show through the inset.
        backgroundColor = .clear

        // The panel measures this view, so the square preview is declared here rather than by
        // whatever hosts it.
        heightAnchor.constraint(equalTo: widthAnchor).isActive = true

        addSubview(placeholderView)
        placeholderView.backgroundColor = .bgSurfaceNested
        placeholderView.layer.cornerRadius = DSRadii.extraLarge
        placeholderView.layer.masksToBounds = true
        placeholderView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(DSSpacings.tiny)
        }

        addSubview(qrFrameView)
        qrFrameView.alpha = 0
        qrFrameView.layer.cornerRadius = DSRadii.extraLarge
        qrFrameView.layer.masksToBounds = true
        qrFrameView.fillColor = .clear
        qrFrameView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(DSSpacings.tiny)
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
}
