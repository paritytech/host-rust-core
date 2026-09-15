import Foundation
import Operation_iOS
import Foundation_iOS
import UIKitExt
import ChainRegistry

protocol SearchAccountViewProtocol: ControllerBackedProtocol {
    var viewModel: SearchAccountViewModel { get }
    func didReceive(_ viewModel: SearchAccountViewModel)
    func applyData(_ viewModel: SearchAccountViewModel)
    func didStartLoading()
    func didStopLoading()
}

@MainActor
protocol SearchAccountPresenterProtocol: AnyObject {
    func viewDidLoad()
    func scanQRCode()
    func didEndEditingInput(_ input: String?)
    func searchAccount(_ account: String?)
    func selectAccount(_ cellType: SearchAccountViewController.Cell)
}

protocol SearchAccountInteractorInputProtocol: AnyObject {
    func setup()
    func subscribeToRecentContacts(for chainAsset: ChainAsset)
    func searchAccount(for input: String)
}

@MainActor
protocol SearchAccountInteractorOutputProtocol: AnyObject {
    func didFetchAllContacts(_ accounts: [UsernameResponseModel])
    func didFindSearchResults(_ accounts: [UsernameResponseModel])
    func didReceiveSearchError(message: String?)
    func didReceiveRecentContacts(_ contacts: [DataProviderChange<RecentContactModelWithUsername>])
}

@MainActor
protocol SearchAccountWireframeProtocol: AnyObject, WalletQRScanPresentable, AlertPresentable {
    func showQRScan(from view: SearchAccountViewProtocol?)
    func showTransfer(
        from view: SearchAccountViewProtocol?,
        recipient: RecipientModel,
        chainAsset: ChainAsset
    )
}
