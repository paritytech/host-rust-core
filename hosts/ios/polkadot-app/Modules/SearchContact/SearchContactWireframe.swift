import Foundation
import Coinage

@MainActor
final class SearchContactWireframe: SearchContactWireframeProtocol {
    let model: SearchContactModel

    private lazy var qrScanResultHandler = WalletQRScanResultHandler(
        dsfinvkRouter: W3sDsfinvkRouter.createDefault(coinageService: coinageService)
    )

    private let coinageService: CoinageServicing

    init(model: SearchContactModel, coinageService: CoinageServicing) {
        self.model = model
        self.coinageService = coinageService
    }

    func showQRScan(from view: SearchContactViewProtocol?) {
        showWalletQRScan(from: view, resultHandler: qrScanResultHandler)
    }

    func complete(from view: SearchContactViewProtocol?, with model: ChatOpenModel) {
        view?.controller.dismiss(animated: true) { [weak self] in
            self?.model.didFoundChat(model)
        }
    }
}
