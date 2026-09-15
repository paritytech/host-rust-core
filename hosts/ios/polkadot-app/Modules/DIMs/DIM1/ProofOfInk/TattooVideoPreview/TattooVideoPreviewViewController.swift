import UIKit
import Foundation_iOS
import FoundationExt

final class TattooVideoPreviewViewController: UIViewController, ViewHolder {
    typealias RootViewType = TattooVideoPreviewViewLayout

    let presenter: TattooVideoPreviewPresenterProtocol

    init(presenter: TattooVideoPreviewPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TattooVideoPreviewViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        customizeBackButton()
        setupLocalization()
        setupHandlers()
        setupInitialState()
        presenter.setup()
    }

    private func setupInitialState() {
        rootView.actionLoadingView.startLoading()
        rootView.playerView.startLoading()
    }
}

private extension TattooVideoPreviewViewController {
    func customizeBackButton() {
        let backButton = UIBarButtonItem(
            image: .buttonBack,
            style: .plain,
            target: self,
            action: #selector(didTapBackButton)
        )
        navigationItem.leftBarButtonItem = backButton
    }

    func setupTitleView() {
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

    func setupLocalization() {
        setupTitleView()

        rootView.actionButton.imageWithTitleView?.title = String(localized: .Tattoo.evidenceVideoNext)
    }

    func setupHandlers() {
        rootView.actionButton.addTarget(self, action: #selector(actionNextEvidence), for: .touchUpInside)
    }

    @objc
    func actionNextEvidence() {
        presenter.nextEvidence()
    }

    @objc
    func didTapBackButton() {
        presenter.confirmDiscard()
    }
}

extension TattooVideoPreviewViewController: TattooVideoPreviewViewProtocol {
    func didReceive(videoUrl: URL) {
        rootView.actionLoadingView.stopLoading()
        rootView.playerView.play(url: videoUrl)
    }
}

extension TattooVideoPreviewViewController: Localizable {
    func applyLocalization() {
        if isViewLoaded {
            setupLocalization()
        }
    }
}
