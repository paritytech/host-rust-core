import UIKit
import FoundationExt
import DesignSystem

final class TattooPhotoPreviewViewController: UIViewController, ViewHolder {
    typealias RootViewType = TattooPhotoPreviewViewLayout

    let presenter: TattooPhotoPreviewPresenterProtocol

    init(presenter: TattooPhotoPreviewPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TattooPhotoPreviewViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        customizeBackButton()
        setupNavigationTitle()
        setupActions()
        presenter.setup()
    }
}

extension TattooPhotoPreviewViewController: TattooPhotoPreviewViewProtocol {
    func didReceive(viewModel: TattooPhotoPreviewViewModel) {
        rootView.bind(viewModel: viewModel)
    }

    func didStartLoading() {
        rootView.actionView.bind(state: .loading)
    }

    func didStopLoading() {
        rootView.actionView.bind(state: .confirm)
    }
}

private extension TattooPhotoPreviewViewController {
    func customizeBackButton() {
        let backButton = UIBarButtonItem(
            image: .buttonBack,
            style: .plain,
            target: self,
            action: #selector(didTapBackButton)
        )
        navigationItem.leftBarButtonItem = backButton
    }

    @objc
    func didTapBackButton() {
        presenter.confirmDiscard()
    }

    func setupActions() {
        rootView.actionView.actionButton.addTarget(
            self,
            action: #selector(didTapDone),
            for: .touchUpInside
        )
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
    func didTapDone() {
        presenter.finishPreview()
    }
}
