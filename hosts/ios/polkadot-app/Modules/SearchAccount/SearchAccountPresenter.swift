import Foundation
import Foundation_iOS
import ChainRegistry
import SubstrateSdkExt

@MainActor
final class SearchAccountPresenter {
    // MARK: Properties

    weak var view: SearchAccountViewProtocol?
    let wireframe: SearchAccountWireframeProtocol
    let interactor: SearchAccountInteractorInputProtocol
    private let chainAsset: ChainAsset
    private var addressInputViewModel = InputViewModel.createAccountInputViewModel(for: "")
    private let recipientViewModelFactory: RecipientViewModelFactoryProtocol

    init(
        interactor: SearchAccountInteractorInputProtocol,
        wireframe: SearchAccountWireframeProtocol,
        recipientViewModelFactory: RecipientViewModelFactoryProtocol,
        chainAsset: ChainAsset
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.recipientViewModelFactory = recipientViewModelFactory
        self.chainAsset = chainAsset
    }

    private func provideAddressInputViewModel(_ accountType: SearchAccountViewModel.AccountType? = nil) {
        guard let view else { return }

        view.didReceive(
            SearchAccountViewModel(
                inputViewModel: SearchAccountViewModel.InputModel(
                    inputViewModel: addressInputViewModel,
                    selectedAccount: accountType
                ),
                content: view.viewModel.content
            )
        )
    }

    private func handleAccountSelection(_ accountType: SearchAccountViewModel.AccountType) {
        addressInputViewModel = InputViewModel.createAccountInputViewModel(for: accountType.title)
        provideAddressInputViewModel(accountType)
    }

    private func updateViewModel(content: SearchAccountViewModel.Content) {
        let viewModel = SearchAccountViewModel(
            inputViewModel: SearchAccountViewModel.InputModel(
                inputViewModel: addressInputViewModel
            ),
            content: content
        )
        view?.applyData(viewModel)
    }

    private static func mapToAccountType(
        _ contact: SearchAccountResult.Contact
    ) -> SearchAccountViewModel.AccountType {
        guard let username = contact.username, !username.isEmpty else {
            return .accountAddress(contact.address)
        }
        return .username(username, contact.address)
    }
}

// MARK: - SearchAccountPresenterProtocol

extension SearchAccountPresenter: SearchAccountPresenterProtocol {
    func viewDidLoad() {
        interactor.setup()
        provideAddressInputViewModel()
    }

    func scanQRCode() {
        wireframe.showQRScan(from: view)
    }

    func searchAccount(_ account: String?) {
        interactor.searchAccount(for: account)
    }

    func selectAccount(_ cellType: SearchAccountViewController.Cell) {
        switch cellType {
        case let .globalContact(accountType):
            interactor.resolveChat(for: accountType.accountAddress)
        case .account,
             .recentContact:
            handleAccountSelection(cellType.accountType)
            guard let recipient = try? RecipientModel(accountType: cellType.accountType) else { return }
            wireframe.showTransfer(from: view, recipient: recipient, chainAsset: chainAsset)
        }
    }

    func didEndEditingInput(_ input: String?) {
        guard
            let inputText = input?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !inputText.isEmpty
        else {
            return
        }

        let isValidAddress = (try? inputText.toAccountId(using: chainAsset.chain.chainFormat)) != nil

        let accountType: SearchAccountViewModel.AccountType = isValidAddress
            ? .accountAddress(inputText)
            : .username(inputText, inputText)

        provideAddressInputViewModel(accountType)
    }
}

// MARK: - SearchAccountInteractorOutputProtocol

extension SearchAccountPresenter: SearchAccountInteractorOutputProtocol {
    func didReceive(searchState: SearchAccountSearchState) {
        switch searchState {
        case .started,
             .waiting,
             .waitingLong:
            view?.didStartLoading()
        case let .result(result):
            view?.didStopLoading()

            updateViewModel(
                content: SearchAccountViewModel.Content(
                    recent: recipientViewModelFactory.createRecentContacts(from: result.recent),
                    contacts: result.contacts.map(Self.mapToAccountType),
                    global: result.global.map(Self.mapToAccountType)
                )
            )
        }
    }

    func didResolveChat(_ model: ChatOpenModel) {
        wireframe.showChat(model)
    }

    func didReceiveSearchError(message: String?) {
        wireframe.present(
            message: message,
            title: String(localized: .Common.error),
            closeAction: String(localized: .Common.close),
            from: view
        )
    }
}
