import UIKit
import FoundationExt
import UIKitExt

final class DepositLostViewController: UIViewController, ControllerBackedProtocol, ViewHolder {
    typealias RootViewType = DepositLostViewLayout

    let presenter: DepositLostPresenterProtocol

    init(presenter: DepositLostPresenterProtocol) {
        self.presenter = presenter
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = DepositLostViewLayout()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        presenter.setup()
        setupHandlers()
    }
}

private extension DepositLostViewController {
    func setupHandlers() {
        rootView.closeButton.addTarget(
            self,
            action: #selector(closeAction),
            for: .touchUpInside
        )
    }

    @objc func closeAction() {
        dismiss(animated: true)
    }
}

extension DepositLostViewController: DepositLostViewProtocol {
    func didReceive(viewModel: DepositLostViewLayout.ViewModel) {
        rootView.bind(viewModel: viewModel)
    }
}
