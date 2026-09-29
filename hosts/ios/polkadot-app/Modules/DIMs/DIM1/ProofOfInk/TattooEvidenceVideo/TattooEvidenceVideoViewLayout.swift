import UIKit
import UIKit_iOS
import AVFoundation
import PolkadotUI
import DesignSystem

final class TattooEvidenceVideoViewLayout: UIView, AppAdaptiveDesignable {
    enum Constants {
        static let progressTop: CGFloat = 16
    }

    let titleLabel: Label = .create { label in
        label.typography = .titleLarge
        label.textColor = .textAndIconsPrimaryDark
    }

    let cameraView: CameraFrameView = .create { view in
        view.windowSize = .zero
        view.fillColor = .clear
    }

    let progressView: ProgressView = .create { view in
        view.fillColor = .fill30
        view.progressColor = .textAndIconsPrimaryDark
        view.cornerRadius = 3
    }

    let timerLabel: Label = .create { view in
        view.typography = .titleMedium
        view.textColor = .white100
    }

    let tipsButton: RoundedButton = .create { button in
        button.applyTipsStyle()
        button.imageWithTitleView?.iconImage = .photoTips
    }

    let recordButton = RecordButton()

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
        videoLayer.frame = cameraView.bounds

        cameraView.frameLayer = videoLayer
    }

    func updateProgressViewOffset(_ offset: CGFloat) {
        progressView.snp.updateConstraints { make in
            make.top.equalToSuperview().offset(Constants.progressTop + offset)
        }
    }

    private func setupStyle() {
        backgroundColor = .black100
    }

    private func setupLayout() {
        addSubview(cameraView)
        cameraView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalToSuperview()
            make.height.equalTo(snp.width)
        }

        addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview().inset(32)
            make.top.equalToSuperview().offset(Constants.progressTop)
            make.height.equalTo(6)
        }

        let scaleCoeff = isAdaptiveHeightDecreased ? designScaleRatio.height : 1

        addSubview(recordButton)
        recordButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.height.equalTo(90 * scaleCoeff)
            make.bottom.equalTo(safeAreaLayoutGuide.snp.bottom).offset(-11 * scaleCoeff)
        }

        let timerWrapperView = UIView()
        timerWrapperView.backgroundColor = .clear
        addSubview(timerWrapperView)
        timerWrapperView.snp.makeConstraints { make in
            make.top.equalTo(cameraView.snp.bottom)
            make.bottom.equalTo(recordButton.snp.top)
            make.leading.trailing.equalToSuperview()
        }

        timerWrapperView.addSubview(timerLabel)
        timerLabel.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        addSubview(tipsButton)
        tipsButton.snp.makeConstraints { make in
            make.top.equalTo(cameraView.snp.bottom).offset(11 * scaleCoeff)
            make.centerX.equalToSuperview()
            make.height.equalTo(40)
        }
    }
}
