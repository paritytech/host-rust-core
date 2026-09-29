import Foundation
import SubstrateSdk
import UIKitExt

struct ConfirmDepositModel {
    let confirmHandler: (ConfirmedDeposit) -> Void
    let cancelHandler: () -> Void
}

struct ConfirmedDeposit {
    let amount: Balance
    let chainAssetId: ChainAssetId
}

protocol ConfirmDepositViewProtocol: ControllerBackedProtocol {
    func didReceive(amountString: String)
    func didReceive(isLoading: Bool)
}

@MainActor
protocol ConfirmDepositPresenterProtocol: AnyObject {
    func setup()
    func didTapConfirm()
    func didDismiss()
}

protocol ConfirmDepositInteractorInputProtocol: AnyObject {
    func setup()
    func didTapConfirm(amount: Balance)
}

@MainActor
protocol ConfirmDepositInteractorOutputProtocol: AnyObject {
    func didStartDeposit()
    func didFinishDeposit()
    func didFailDeposit(_ error: Error)
}
