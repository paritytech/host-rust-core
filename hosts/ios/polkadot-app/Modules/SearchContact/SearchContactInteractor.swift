import UIKit
import Operation_iOS
import SubstrateSdk

final class SearchContactInteractor {
    weak var presenter: SearchContactInteractorOutputProtocol?

    private let searchApi: RemoteContactOperationMaking
    private let chatRepositoryFactory: ChatRepositoryMaking
    private let ownAccountId: AccountId
    private let searchRunner = SearchRunner()
    private var searchTask: Task<Void, Never>?

    init(
        ownAccountId: AccountId,
        searchApi: RemoteContactOperationMaking = RemoteContactOperationFactory(),
        chatRepositoryFactory: ChatRepositoryMaking = ChatRepositoryFactory()
    ) {
        self.ownAccountId = ownAccountId
        self.searchApi = searchApi
        self.chatRepositoryFactory = chatRepositoryFactory
    }

    deinit {
        cancelSearchTask()
    }
}

extension SearchContactInteractor: SearchContactInteractorInputProtocol {
    func search(username: String) {
        cancelSearchTask()

        guard !username.isEmpty else {
            searchTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                await self?.presenter?.didReceive(searchState: .result(.contacts([])), for: username)
            }
            return
        }

        searchTask = Task { [weak presenter, searchRunner, searchApi, ownAccountId] in
            let stateStream = searchRunner.run {
                await Self.makeSearchResult(
                    for: username,
                    ownAccountId: ownAccountId,
                    searchApi: searchApi
                )
            }
            for await state in stateStream {
                guard !Task.isCancelled else { return }
                await presenter?.didReceive(searchState: state, for: username)
            }
        }
    }

    func decide(on contact: Chat.RemoteContact) {
        let chatRepository = chatRepositoryFactory.createRepository(
            forFilter: .contact(for: contact.accountId)
        )

        Task { [weak self] in
            do {
                let chats = try await chatRepository.fetchAllOperation(with: RepositoryFetchOptions()).asyncExecute()

                let openModel: ChatOpenModel
                if let chat = chats.first {
                    openModel = .existingChat(chat.chatId)
                } else {
                    let newRequest = try ChatOpenModel.NewRequest(
                        remoteContact: contact,
                        ownKeyId: Chat.Contact.Own.main()
                    )
                    openModel = .newRequest(newRequest)
                }
                await self?.presenter?.didReceive(resolution: openModel)
            } catch {
                await self?.presenter?.didReceive(error: error)
            }
        }
    }
}

private extension SearchContactInteractor {
    func cancelSearchTask() {
        searchTask?.cancel()
        searchTask = nil
    }

    static func makeSearchResult(
        for query: String,
        ownAccountId: AccountId,
        searchApi: RemoteContactOperationMaking
    ) async -> SearchContactSearchResult? {
        do {
            if let accountId = try? query.toAccountId(),
               accountId != ownAccountId,
               let account = try? await searchApi.fetch(by: accountId) {
                try Task.checkCancellation()
                return .contacts([account])
            }
            let contacts = try await searchApi.search(by: query).asyncExecute()
            let matchedContacts = contacts.filter { $0.accountId != ownAccountId }
            try Task.checkCancellation()
            return .contacts(matchedContacts)
        } catch {
            guard !Task.isCancelled else { return nil }
            return .error(error)
        }
    }
}
