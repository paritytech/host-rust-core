import UIKit
import AVFoundation
import Foundation_iOS
import FoundationExt

final class TattooEvidenceVideoViewController: UIViewController, ViewHolder {
    typealias RootViewType = TattooEvidenceVideoViewLayout

    let presenter: TattooEvidenceVideoPresenterProtocol

    init(presenter: TattooEvidenceVideoPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TattooEvidenceVideoViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupLocalization()
        setupProgressOffset()
        setupHandlers()
        presenter.setup()
    }

    private func setupProgressOffset() {
        let navBarHeight: CGFloat = navigationController?.navigationBar.frame.height ?? 0
        let statusBarHeight: CGFloat = UIApplication.statusBarHeight
        rootView.updateProgressViewOffset(navBarHeight + statusBarHeight)
    }

    private func setupTitleView() {
        let title = NSAttributedString.coloredItems(
            [String(localized: .Tattoo.evidenceVideoTitlePrefix)],
            formattingClosure: { items in
                String(localized: .Tattoo.evidenceVideoTitleFormat(items[0]))
            },
            color: .textAndIconsTertiaryDark
        )

        rootView.titleLabel.attributedText = title
        navigationItem.titleView = rootView.titleLabel
    }

    private func setupLocalization() {
        setupTitleView()

        rootView.tipsButton.imageWithTitleView?.title = String(localized: .Tattoo.filmingTips)
    }

    private func setupHandlers() {
        rootView.recordButton.addTarget(
            self,
            action: #selector(actionToggleRecording),
            for: .touchUpInside
        )

        rootView.tipsButton.addTarget(
            self,
            action: #selector(actionTips),
            for: .touchUpInside
        )
    }

    private func configureVideoLayer(with captureSession: AVCaptureSession) {
        if let layer = rootView.cameraView.frameLayer as? AVCaptureVideoPreviewLayer {
            if layer.session === captureSession {
                return
            }

            layer.session = captureSession
        } else {
            let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            rootView.setupVideoLayer(videoPreviewLayer)
        }
    }

    private func setupInitLayout() {
        navigationController?.setNavigationBarHidden(false, animated: true)

        rootView.tipsButton.isHidden = false
        rootView.timerLabel.isHidden = true

        rootView.progressView.setProgress(0, animated: false)
    }

    private func setupRecordingLayout(for progress: CGFloat, time: String) {
        navigationController?.setNavigationBarHidden(true, animated: true)
        rootView.tipsButton.isHidden = true
        rootView.timerLabel.isHidden = false

        rootView.timerLabel.text = time
        rootView.progressView.setProgress(progress, animated: true)
    }

    @objc func actionToggleRecording() {
        presenter.toggleRecording()
    }

    @objc func actionTips() {
        presenter.openTips()
    }
}

extension TattooEvidenceVideoViewController: TattooEvidenceVideoViewProtocol {
    func didReceive(viewModel: TattooEvidenceVideoViewModel) {
        switch viewModel {
        case .initial:
            setupInitLayout()

            rootView.recordButton.viewState = .processing
        case let .sessionReady(optSession):
            if let session = optSession {
                configureVideoLayer(with: session)
            }

            setupInitLayout()

            rootView.recordButton.viewState = .actionable
        case let .recording(progress, time):
            setupRecordingLayout(for: progress, time: time)

            rootView.recordButton.viewState = .recording
        case let .processing(progress, time):
            setupRecordingLayout(for: progress, time: time)

            rootView.recordButton.viewState = .processing
        }
    }
}

extension TattooEvidenceVideoViewController: Localizable {
    func applyLocalization() {
        if isViewLoaded {
            setupLocalization()
        }
    }
}
