import Foundation
import UIKitExt
import PolkadotUI
import ChainRegistry

protocol WalletMainViewProtocol: ControllerBackedProtocol {
    func didReceive(isCollectiblesAvailable: Bool)
    func didReceive(titleViewModel: NetworkStatusTitleView.ViewModel)
}

@MainActor
protocol WalletMainPresenterProtocol: AnyObject {
    func setup()
    func showCollectibles()
}

@MainActor
protocol WalletMainWireframeProtocol: AnyObject {
    func showCollectibles(from view: WalletMainViewProtocol?, url: URL)
}

protocol WalletMainInteractorInputProtocol: AnyObject {
    func setup()
}

@MainActor
protocol WalletMainInteractorOutputProtocol: AnyObject {
    func didReceiveCollectibles(url: URL?)
    func didReceive(networkStatus: NetworkStatus)
}
