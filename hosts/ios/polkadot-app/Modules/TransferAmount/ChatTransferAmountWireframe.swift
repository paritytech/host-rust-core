import Foundation
import SubstrateSdk
import UIKit
import UIKitExt
import Foundation_iOS
import PolkadotUI
import ChainRegistry

@MainActor
final class ChatTransferAmountWireframe: TransferAmountWireframeProtocol {
    let chainAsset: ChainAsset

    init(chainAsset: ChainAsset) {
        self.chainAsset = chainAsset
    }

    func presentTransactionSuccess(
        from _: (any ControllerBackedProtocol)?,
        onDone: TransactionSuccessCompletion?
    ) {
        onDone?()
    }

    func hide(view: (any ControllerBackedProtocol)?) {
        view?.controller.dismiss(animated: true)
    }

    func showBalanceInfo(model: BalanceInfoModel, from view: (any ControllerBackedProtocol)?) {
        let sheet = BalanceInfoViewFactory.createView(from: model)
        view?.controller.present(sheet, animated: true)
    }
}
