import PolkadotUI
import UIKitExt

protocol SearchContactViewProtocol: ControllerBackedProtocol {
    func didReceive(viewModel: SearchContactViewLayout.ViewModel)
}

@MainActor
protocol SearchContactPresenterProtocol: AnyObject {
    func setup()
    func search(username: String)
    func scanQRCode()
    func didSelectContact(identifier: String)
}

protocol SearchContactInteractorInputProtocol: AnyObject {
    func search(username: String)
    func decide(on contact: Chat.RemoteContact)
}

@MainActor
protocol SearchContactInteractorOutputProtocol: AnyObject {
    func didReceive(searchState: SearchContactSearchState, for query: String)
    func didReceive(error: Error)
    func didReceive(resolution: ChatOpenModel)
}

@MainActor
protocol SearchContactWireframeProtocol: AnyObject, WalletQRScanPresentable, AlertPresentable, ErrorPresentable {
    func showQRScan(from view: SearchContactViewProtocol?)
    func complete(from view: SearchContactViewProtocol?, with model: ChatOpenModel)
}
