import Foundation
import SubstrateSdk

final class GameDepositRequiredPresenter {
    weak var view: GameDepositRequiredViewProtocol?
    let model: GameDepositRequiredModel
    let viewModelFactory: GameDepositRequiredViewModelMaking

    private let requiredBalance: Balance

    init(
        requiredBalance: Balance,
        model: GameDepositRequiredModel,
        viewModelFactory: GameDepositRequiredViewModelMaking
    ) {
        self.requiredBalance = requiredBalance
        self.model = model
        self.viewModelFactory = viewModelFactory
    }
}

extension GameDepositRequiredPresenter: GameDepositRequiredPresenterProtocol {
    func setup() {
        let amountString = viewModelFactory.formatAmount(requiredBalance)
        view?.didReceive(amountString: amountString)
    }

    func didTapDeposit() {
        model.depositHandler()
    }

    func didDismiss() {
        model.cancelHandler()
    }
}
