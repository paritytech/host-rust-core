import UIKit
import Operation_iOS
import SubstrateSdk
import ChainRegistry

final class SearchAccountInteractor {
    // MARK: Properties

    weak var presenter: SearchAccountInteractorOutputProtocol?

    private let searchUsernameFactory: SearchUsernameOperationFactory
    private let recentContactsManager: RecentContactsManaging
    private let debouncer = Debouncer(delay: 0.5, queue: .main)
    private var searchTask: Task<Void, Never>?
    private let logger: LoggerProtocol

    // MARK: Initial methods

    init(
        searchUsernameFactory: SearchUsernameOperationFactory,
        recentContactsManager: RecentContactsManaging,
        logger: LoggerProtocol
    ) {
        self.searchUsernameFactory = searchUsernameFactory
        self.recentContactsManager = recentContactsManager
        self.logger = logger
    }

    deinit {
        searchTask?.cancel()
    }
}

// MARK: - SearchAccountInteractorInputProtocol

extension SearchAccountInteractor: SearchAccountInteractorInputProtocol {
    func setup() {
        Task { [weak presenter, searchUsernameFactory, logger] in
            do {
                let accounts = try await searchUsernameFactory.allUsernames()
                try Task.checkCancellation()

                await presenter?.didFetchAllContacts(accounts)
            } catch {
                logger.debug("Fetch all contacts failed \(error)")
            }
        }
    }

    func subscribeToRecentContacts(for chainAsset: ChainAsset) {
        recentContactsManager.setup(self, chainAssetID: chainAsset.chainAssetId)
    }

    func searchAccount(for input: String) {
        searchTask?.cancel()

        debouncer.debounce { [weak self] in
            self?.performSearch(query: input)
        }
    }
}

// MARK: - RecentContactsServiceDelegate

extension SearchAccountInteractor: RecentContactsServiceDelegate {
    func recentContactsServiceDidUpdate(recentContacts: [DataProviderChange<RecentContactModelWithUsername>]) {
        Task { [weak presenter] in
            await presenter?.didReceiveRecentContacts(recentContacts)
        }
    }

    func recentContactServiceDidFail(error: any Error) {
        logger.error(error.localizedDescription)
        Task { [weak presenter] in
            await presenter?.didReceiveRecentContacts([])
        }
    }
}

// MARK: - Private

private extension SearchAccountInteractor {
    func performSearch(query: String) {
        searchTask?.cancel()

        searchTask = Task { [weak self, logger] in
            do {
                let accounts = try await self?.searchUsernameFactory.searchUsername(
                    for: UsernameRequestModel(prefix: query)
                ) ?? []

                try Task.checkCancellation()
                await self?.presenter?.didFindSearchResults(accounts)
            } catch {
                guard !Task.isCancelled else { return }

                logger.debug(error.localizedDescription)
                await self?.presenter?.didReceiveSearchError(message: error.localizedDescription)
            }
        }
    }
}
