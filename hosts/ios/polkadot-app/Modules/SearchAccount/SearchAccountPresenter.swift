import Foundation
import Foundation_iOS
import Operation_iOS
import SubstrateSdk
import ChainRegistry
import SubstrateSdkExt

@MainActor
final class SearchAccountPresenter {
    // MARK: Properties

    static let maxRecentContactsDisplay = 5

    weak var view: SearchAccountViewProtocol?
    let wireframe: SearchAccountWireframeProtocol
    let interactor: SearchAccountInteractorInputProtocol
    private let chainAsset: ChainAsset
    private let logger: LoggerProtocol
    private var addressInputViewModel = InputViewModel.createAccountInputViewModel(for: "")
    private let recipientViewModelFactory: RecipientViewModelFactoryProtocol
    private var recentContactsMap = [String: RecentContactModelWithUsername]()
    private var allContacts: [UsernameResponseModel] = []
    private var currentQuery: String?

    init(
        interactor: SearchAccountInteractorInputProtocol,
        wireframe: SearchAccountWireframeProtocol,
        recipientViewModelFactory: RecipientViewModelFactoryProtocol,
        logger: LoggerProtocol,
        chainAsset: ChainAsset
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.recipientViewModelFactory = recipientViewModelFactory
        self.logger = logger
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
                dataType: view.viewModel.dataType
            )
        )
    }

    private func handleAccountSelection(_ accountType: SearchAccountViewModel.AccountType) {
        addressInputViewModel = InputViewModel.createAccountInputViewModel(for: accountType.title)
        provideAddressInputViewModel(accountType)
    }

    private func mapToAccountType(from model: UsernameResponseModel) -> SearchAccountViewModel.AccountType {
        .username(model.username.value, model.accountId)
    }

    private func mapToAccountType(from accountAddress: AccountAddress) -> SearchAccountViewModel.AccountType {
        .accountAddress(accountAddress)
    }

    private func isAccountAddress(_ inputText: String) -> Bool {
        guard (try? inputText.toAccountId(using: chainAsset.chain.chainFormat)) != nil else {
            logger.debug("Invalid account address format")
            return false
        }
        return true
    }

    private func updateViewModel(dataType: SearchAccountViewModel.DataType) {
        let viewModel = SearchAccountViewModel(
            inputViewModel: SearchAccountViewModel.InputModel(
                inputViewModel: addressInputViewModel
            ),
            dataType: dataType
        )
        view?.applyData(viewModel)
    }

    private func updateIdleViewModel() {
        let recent = recipientViewModelFactory.createRecentContacts(from: recentContactsMap)
            .prefix(Self.maxRecentContactsDisplay)
        let contacts = allContacts.map { mapToAccountType(from: $0) }

        let filtered = contacts.filter { contact in
            !recent.contains(where: { $0.accountType == contact })
        }

        updateViewModel(dataType: .idle(recent: Array(recent), contacts: filtered))
    }
}

// MARK: - SearchAccountPresenterProtocol

extension SearchAccountPresenter: SearchAccountPresenterProtocol {
    func viewDidLoad() {
        interactor.setup()
        interactor.subscribeToRecentContacts(for: chainAsset)
        provideAddressInputViewModel()
    }

    func scanQRCode() {
        wireframe.showQRScan(from: view)
    }

    func searchAccount(_ account: String?) {
        guard
            let inputText = account?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !inputText.isEmpty
        else {
            currentQuery = nil
            return updateIdleViewModel()
        }

        currentQuery = inputText

        if isAccountAddress(inputText) {
            updateViewModel(dataType: .searchResults([mapToAccountType(from: inputText)]))
        } else if inputText.count <= .maximumPrefixCount {
            interactor.searchAccount(for: inputText.trimmingDot())
            view?.didStartLoading()
        } else {
            updateViewModel(dataType: .searchResults([]))
        }
    }

    func selectAccount(_ cellType: SearchAccountViewController.Cell) {
        handleAccountSelection(cellType.accountType)
        guard let recipient = try? RecipientModel(accountType: cellType.accountType) else { return }

        wireframe.showTransfer(from: view, recipient: recipient, chainAsset: chainAsset)
    }

    func didEndEditingInput(_ input: String?) {
        guard
            let inputText = input?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !inputText.isEmpty
        else {
            return
        }

        let accountType: SearchAccountViewModel.AccountType = isAccountAddress(inputText) ?
            mapToAccountType(from: inputText) :
            .username(inputText, inputText)

        provideAddressInputViewModel(accountType)
    }
}

// MARK: - SearchAccountInteractorOutputProtocol

extension SearchAccountPresenter: SearchAccountInteractorOutputProtocol {
    func didFetchAllContacts(_ accounts: [UsernameResponseModel]) {
        let sorted = accounts.sorted { $0.username < $1.username }
        allContacts = sorted
        guard currentQuery == nil else { return }
        updateIdleViewModel()
    }

    func didFindSearchResults(_ accounts: [UsernameResponseModel]) {
        view?.didStopLoading()
        guard currentQuery != nil else { return }
        let sorted = accounts.sorted { $0.username < $1.username }
        updateViewModel(dataType: .searchResults(sorted.map { mapToAccountType(from: $0) }))
    }

    func didReceiveSearchError(message: String?) {
        wireframe.present(
            message: message,
            title: String(localized: .Common.error),
            closeAction: String(localized: .Common.close),
            from: view
        )
    }

    func didReceiveRecentContacts(_ contacts: [DataProviderChange<RecentContactModelWithUsername>]) {
        guard !contacts.isEmpty else { return }
        recentContactsMap = contacts.mergeToDict(recentContactsMap)
        guard currentQuery == nil else { return }
        updateIdleViewModel()
    }
}

// MARK: - Constants

private extension Int {
    static let maximumPrefixCount = 32
}
