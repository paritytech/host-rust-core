import Foundation
import SubstrateSdk
import ChainRegistry

final class ConfirmDepositPresenter {
    weak var view: ConfirmDepositViewProtocol?
    let interactor: ConfirmDepositInteractorInputProtocol

    let model: ConfirmDepositModel
    let viewModelFactory: ConfirmDepositViewModelMaking

    private let amount: Balance
    private let chainAsset: ChainAsset

    init(
        interactor: ConfirmDepositInteractorInputProtocol,
        amount: Balance,
        chainAsset: ChainAsset,
        model: ConfirmDepositModel,
        viewModelFactory: ConfirmDepositViewModelMaking
    ) {
        self.amount = amount
        self.chainAsset = chainAsset
        self.model = model
        self.viewModelFactory = viewModelFactory
        self.interactor = interactor
    }
}

extension ConfirmDepositPresenter: ConfirmDepositPresenterProtocol {
    func setup() {
        let amountString = viewModelFactory.formatAmount(amount)
        view?.didReceive(amountString: amountString)
    }

    func didTapConfirm() {
        interactor.didTapConfirm(amount: amount)
    }

    func didDismiss() {
        model.cancelHandler()
    }
}

extension ConfirmDepositPresenter: ConfirmDepositInteractorOutputProtocol {
    func didStartDeposit() {
        view?.didReceive(isLoading: true)
    }

    func didFinishDeposit() {
        view?.didReceive(isLoading: false)

        model.confirmHandler(
            ConfirmedDeposit(
                amount: amount,
                chainAssetId: chainAsset.chainAssetId
            )
        )
    }

    func didFailDeposit(_: Error) {
        view?.didReceive(isLoading: false)
    }
}
