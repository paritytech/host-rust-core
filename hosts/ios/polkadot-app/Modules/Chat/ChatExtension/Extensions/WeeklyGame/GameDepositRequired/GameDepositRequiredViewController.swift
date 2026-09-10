import UIKit
import SwiftUI
import PolkadotUI
import UIKit_iOS

final class GameDepositRequiredViewController: UIHostingController<GameDepositRequiredView> {
    let presenter: GameDepositRequiredPresenterProtocol

    init(presenter: GameDepositRequiredPresenterProtocol) {
        self.presenter = presenter
        super.init(rootView: GameDepositRequiredView(requiredAmount: ""))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        setupHandlers()
        presenter.setup()
    }

    private func setupHandlers() {
        rootView.onDepositTapped = { [weak presenter] in
            presenter?.didTapDeposit()
        }
    }
}

extension GameDepositRequiredViewController: GameDepositRequiredViewProtocol {
    func didReceive(amountString: String) {
        rootView.requiredAmount = amountString
    }
}

extension GameDepositRequiredViewController: ModalPresenterDelegate {
    func presenterDidHide(_: any ModalPresenterProtocol) {
        presenter.didDismiss()
    }
}
