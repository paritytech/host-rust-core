import UIKit
import SwiftUI
import PolkadotUI
import UIKit_iOS

final class ConfirmDepositViewController: UIHostingController<ConfirmDepositView> {
    let presenter: ConfirmDepositPresenterProtocol
    private var isLoading: Bool = false

    init(presenter: ConfirmDepositPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: ConfirmDepositView(amount: ""))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .bgSurfaceMain
        setupHandlers()
        presenter.setup()
    }

    private func setupHandlers() {
        rootView.onConfirmTapped = { [weak presenter] in
            presenter?.didTapConfirm()
        }
    }
}

extension ConfirmDepositViewController: ConfirmDepositViewProtocol {
    func didReceive(amountString: String) {
        rootView.amount = amountString
    }

    func didReceive(isLoading: Bool) {
        self.isLoading = isLoading
        rootView.isLoading = isLoading
    }
}

extension ConfirmDepositViewController: ModalPresenterDelegate {
    func presenterShouldHide(_: any ModalPresenterProtocol) -> Bool {
        !isLoading
    }

    func presenterDidHide(_: any ModalPresenterProtocol) {
        presenter.didDismiss()
    }
}
