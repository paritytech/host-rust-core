import Foundation_iOS
import UIKit
import PolkadotUI
import FoundationExt

final class TattooCommitViewController: UIViewController, ViewHolder {
    typealias RootViewType = TattooCommitViewLayout

    let presenter: TattooCommitPresenterProtocol

    init(presenter: TattooCommitPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = TattooCommitViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupHandlers()
        setupLocalization()

        presenter.setup()
    }

    private func setupHandlers() {
        rootView.actionButton.addTarget(
            self,
            action: #selector(actionProceed),
            for: .touchUpInside
        )
    }

    private func setupLocalization() {
        rootView.actionButton.imageWithTitleView?.title = String(localized: .Tattoo.commitActionTitle)
    }

    @objc func actionProceed() {
        presenter.proceed()
    }
}

extension TattooCommitViewController: TattooCommitViewProtocol {
    func didReceiveDescription(viewModel: TattooCommitListViewModel) {
        rootView.bind(viewModel: viewModel)
    }

    func didStartLoading() {
        rootView.loadableActionView.startLoading()
    }

    func didStopLoading() {
        rootView.loadableActionView.stopLoading()
    }
}

extension TattooCommitViewController: Localizable {
    func applyLocalization() {
        if isViewLoaded {
            setupLocalization()
        }
    }
}
