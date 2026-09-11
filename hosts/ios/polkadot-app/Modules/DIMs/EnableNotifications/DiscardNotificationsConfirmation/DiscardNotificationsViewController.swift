import UIKit
import FoundationExt

final class DiscardNotificationsViewController: UIViewController, ViewHolder {
    typealias RootViewType = DiscardNotificationsViewLayout

    let presenter: DiscardNotificationsPresenterProtocol

    init(presenter: DiscardNotificationsPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = DiscardNotificationsViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        presenter.setup()
        setupHandlers()
    }

    private func setupHandlers() {
        rootView.enableButton.addTarget(
            self,
            action: #selector(enableNotificationPressed),
            for: .touchUpInside
        )

        rootView.discardButton.addTarget(
            self,
            action: #selector(discardNotificationPressed),
            for: .touchUpInside
        )
    }

    @objc func enableNotificationPressed() {
        presenter.enableNotifications()
    }

    @objc func discardNotificationPressed() {
        presenter.discardNotifications()
    }
}

extension DiscardNotificationsViewController: DiscardNotificationsViewProtocol {
    func didReceive(viewModel: DiscardNotificationsViewLayout.ViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}
