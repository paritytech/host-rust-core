import Foundation
import UIKit
import UIKitExt

@MainActor
final class SuccessPaymentWireframe: TransferAmountWireframeProtocol {
    func hide(view: ControllerBackedProtocol?) {
        presentTransactionSuccess(from: view) { [weak view] in
            view?.controller.presentingViewController?.dismiss(animated: true)
        }
    }

    func showBalanceInfo(model: BalanceInfoModel, from view: (any ControllerBackedProtocol)?) {
        let sheet = BalanceInfoViewFactory.createView(from: model)
        view?.controller.present(sheet, animated: true)
    }
}
