import UIKit
import PolkadotUI
import FoundationExt

final class EnableNotificationsViewController: UIViewController, ViewHolder {
    typealias RootViewType = EnableNotificationsViewLayout

    let presenter: EnableNotificationsPresenterProtocol

    init(presenter: EnableNotificationsPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = EnableNotificationsViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setupHandlers()

        presenter.setup()
    }

    private func setupHandlers() {
        rootView.enableButton.addTarget(
            self,
            action: #selector(enableNotificationsPressed),
            for: .touchUpInside
        )

        rootView.ignoreButton.addTarget(
            self,
            action: #selector(ignoreNotificationsPressed),
            for: .touchUpInside
        )
    }

    @objc func enableNotificationsPressed() {
        presenter.enableNotifications()
    }

    @objc func ignoreNotificationsPressed() {
        presenter.discardNotifications()
    }
}

extension EnableNotificationsViewController: EnableNotificationsViewProtocol {
    func didReceive(reasonsViewModel: EnableNotificationsViewLayout.ViewModel) {
        rootView.bind(viewModel: reasonsViewModel)
    }
}
