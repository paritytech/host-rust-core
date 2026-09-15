import UIKit
import Coinage
import ChainRegistry

@MainActor
final class SearchAccountWireframe: SearchAccountWireframeProtocol {
    let coinageServicing: CoinageServicing

    private lazy var qrScanResultHandler = WalletQRScanResultHandler(
        dsfinvkRouter: W3sDsfinvkRouter.createDefault(coinageService: coinageServicing)
    )

    init(coinageServicing: CoinageServicing) {
        self.coinageServicing = coinageServicing
    }

    func showQRScan(from view: SearchAccountViewProtocol?) {
        showWalletQRScan(from: view, resultHandler: qrScanResultHandler)
    }

    func showTransfer(
        from view: SearchAccountViewProtocol?,
        recipient: RecipientModel,
        chainAsset: ChainAsset
    ) {
        guard
            let destination = TransferAmountViewFactory.createTransfer(
                for: chainAsset,
                recipient: recipient,
                coinageService: coinageServicing
            )
        else {
            return
        }

        view?.controller.navigationController?.pushViewController(destination.controller, animated: true)
    }
}
