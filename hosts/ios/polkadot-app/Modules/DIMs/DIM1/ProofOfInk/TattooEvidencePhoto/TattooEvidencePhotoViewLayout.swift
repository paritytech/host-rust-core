import UIKit
import UIKit_iOS
import AVFoundation
import PolkadotUI

struct TattooEvidencePhotoViewModel {
    let tipsAction: String
    let outlineAction: String
    let outlineIcon: UIImage
    let tattooOverlay: ImageViewModelProtocol?
    let isOutlineHidden: Bool
}

enum TattooEvidencePhotoViewState {
    case preparing
    case actionable
    case capturing
    case captured(UIImage)
}

final class TattooEvidencePhotoViewLayout: UIView {
    private let cameraView: CameraFrameView = .create { view in
        view.windowSize = .zero
        view.fillColor = .clear
    }

    let photoPreview: UIImageView = .create { view in
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
    }

    private let tatooOverlay: TattooOutlineView = .create { view in
        view.isHidden = true
    }

    private let additionalActions: GenericPairValueView<RoundedButton, RoundedButton> = .create { view in
        view.setHorizontalAndSpacing(8)
        view.fView.imageWithTitleView?.iconImage = .photoTips
        view.fView.applyCaptionTitleIconStyle()
        view.sView.imageWithTitleView?.iconImage = .tattooOutlineOff
        view.sView.applyCaptionTitleIconStyle()
    }

    var outlineAction: RoundedButton { additionalActions.sView }
    var tipsAction: RoundedButton { additionalActions.fView }

    let photoButton: RecordButton = .init()

    override init(frame: CGRect) {
        super.init(frame: frame)

        setupStyle()
        setupLayout()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupVideoLayer(_ videoLayer: AVCaptureVideoPreviewLayer) {
        videoLayer.videoGravity = AVLayerVideoGravity.resizeAspectFill
        let size = min(bounds.width, bounds.height)
        videoLayer.frame = CGRect(
            x: (bounds.width - size) / 2,
            y: (bounds.height - size) / 2,
            width: size,
            height: size
        )

        cameraView.frameLayer = videoLayer
    }

    func bind(viewModel: TattooEvidencePhotoViewModel) {
        tipsAction.imageWithTitleView?.title = viewModel.tipsAction
        outlineAction.imageWithTitleView?.title = viewModel.outlineAction
        outlineAction.imageWithTitleView?.iconImage = viewModel.outlineIcon
        tatooOverlay.bind(viewModel: viewModel.tattooOverlay)
        tatooOverlay.isHidden = viewModel.isOutlineHidden
    }
}

private extension TattooEvidencePhotoViewLayout {
    func setupStyle() {
        backgroundColor = .black100
    }

    func setupLayout() {
        addSubview(cameraView)
        addSubview(additionalActions)
        addSubview(photoButton)
        insertSubview(tatooOverlay, aboveSubview: cameraView)
        insertSubview(photoPreview, aboveSubview: tatooOverlay)
        cameraView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().priority(.low)
            make.top.greaterThanOrEqualToSuperview().offset(20).priority(.required)
            make.width.equalToSuperview()
            make.height.equalTo(snp.width)
        }
        tatooOverlay.snp.makeConstraints { make in
            make.height.equalTo(cameraView.snp.height)
            make.width.equalTo(cameraView.snp.width)
            make.center.equalTo(cameraView)
        }
        photoPreview.snp.makeConstraints { make in
            make.width.equalToSuperview()
            make.height.equalTo(photoPreview.snp.width)
            make.center.equalTo(cameraView)
        }
        photoButton.snp.makeConstraints { make in
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-22)
            make.centerX.equalToSuperview()
            make.width.equalTo(82)
            make.height.equalTo(photoButton.snp.width)
        }
        additionalActions.snp.makeConstraints { make in
            make.top.equalTo(cameraView.snp.bottom).offset(24)
            make.centerX.equalToSuperview()
            make.height.equalTo(40)
            make.bottom.equalTo(photoButton.snp.top).offset(-24).priority(.required)
        }
    }
}
