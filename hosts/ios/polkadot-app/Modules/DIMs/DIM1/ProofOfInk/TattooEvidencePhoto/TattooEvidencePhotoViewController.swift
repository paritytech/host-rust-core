import AVFoundation
import UIKit
import Foundation_iOS
import FoundationExt
import UIKitExt
import DesignSystem

final class TattooEvidencePhotoViewController: UIViewController, ViewHolder, ControllerBackedProtocol {
    typealias RootViewType = TattooEvidencePhotoViewLayout

    let presenter: TattooEvidencePhotoPresenterProtocol

    init(presenter: TattooEvidencePhotoPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TattooEvidencePhotoViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationTitle()
        setupActions()
        presenter.setup()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        presenter.willAppear()
    }
}

private extension TattooEvidencePhotoViewController {
    func setupActions() {
        rootView.photoButton.addTarget(self, action: #selector(didTapCapturePhoto), for: .touchUpInside)
        rootView.tipsAction.addTarget(self, action: #selector(didTapPhotoTips), for: .touchUpInside)
        rootView.outlineAction.addTarget(self, action: #selector(didTapTattooOutline), for: .touchUpInside)
    }

    func setupNavigationTitle() {
        let formattedTitle = NSAttributedString.highlightedItems(
            [String(localized: .Tattoo.evidencePhotoTitlePrefix)],
            formattingClosure: { items in
                String(localized: .Tattoo.evidencePhotoTitleFormat(items[0]))
            },
            highlightingAttributes: [
                .foregroundColor: UIColor.textAndIconsTertiaryDark,
                .font: UIFont.titleLarge
            ],
            defaultAttributes: [
                .foregroundColor: UIColor.textAndIconsPrimaryDark,
                .font: UIFont.titleLarge
            ]
        )
        let titleLabel = UILabel()
        titleLabel.attributedText = formattedTitle
        titleLabel.sizeToFit()
        navigationItem.titleView = titleLabel
    }

    @objc
    func didTapCapturePhoto() {
        presenter.capturePhoto()
    }

    @objc
    func didTapPhotoTips() {
        presenter.showPhotoTips()
    }

    @objc
    func didTapTattooOutline() {
        presenter.toggleTattooOutline()
    }
}

extension TattooEvidencePhotoViewController: TattooEvidencePhotoViewProtocol {
    func didReceive(session: AVCaptureSession) {
        rootView.setupVideoLayer(AVCaptureVideoPreviewLayer(session: session))
    }

    func didReceive(viewModel: TattooEvidencePhotoViewModel) {
        rootView.bind(viewModel: viewModel)
    }

    func didReceive(state: TattooEvidencePhotoViewState) {
        switch state {
        case .preparing:
            rootView.photoButton.viewState = .processing
            rootView.photoPreview.image = nil
        case .actionable:
            rootView.photoButton.viewState = .actionable
            rootView.photoPreview.image = nil
        case .capturing:
            rootView.photoButton.viewState = .processing
            rootView.photoPreview.image = nil
        case let .captured(image):
            rootView.photoPreview.image = image
        }
    }
}

extension TattooEvidencePhotoViewController: Localizable {
    func applyLocalization() {
        setupNavigationTitle()
    }
}
