import Foundation
import SubstrateSdk
import Operation_iOS
import Individuality

final class ChatWithPlayersInteractor {
    weak var presenter: ChatWithPlayersInteractorOutputProtocol?
    private let repositoryVotes: AnyDataProviderRepository<GameVote>
    private let repositoryContacts: AnyDataProviderRepository<Chat.Contact>
    private let identifierService: ChatIdentifierServiceProtocol
    private let contactsProvider: ChatContactDataProviderMaking
    private let chatRequestService: ChatRequestStoreServicing
    private let personDataStore: DetermineStatePersonDataStore
    private let pushToken: Data?
    private let logger: LoggerProtocol

    private let gameIndex: UInt32
    private let gameDate: Date

    private var fetchTask: Task<Void, Error>?
    private var contactsObserver: Task<Void, Error>?

    init(
        gameIndex: UInt32,
        gameDate: Date,
        repositoryVotes: AnyDataProviderRepository<GameVote>,
        repositoryContacts: AnyDataProviderRepository<Chat.Contact>,
        identifierService: ChatIdentifierServiceProtocol,
        contactsProvider: ChatContactDataProviderMaking = ChatContactDataProviderFactory(),
        chatRequestService: ChatRequestStoreServicing,
        personDataStore: DetermineStatePersonDataStore,
        pushToken: Data?,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.repositoryVotes = repositoryVotes
        self.repositoryContacts = repositoryContacts
        self.identifierService = identifierService
        self.contactsProvider = contactsProvider
        self.gameIndex = gameIndex
        self.gameDate = gameDate
        self.chatRequestService = chatRequestService
        self.personDataStore = personDataStore
        self.pushToken = pushToken
        self.logger = logger
    }

    deinit {
        cancelContactRequest()
        contactsObserver?.cancel()
    }
}

extension ChatWithPlayersInteractor: ChatWithPlayersInteractorInputProtocol {
    func setup() {
        fetchPlayers()

        contactsObserver = Task { [weak self] in
            guard let self else { return }

            do {
                let allContacts = contactsProvider.subscribeAllContacts()
                for try await contacts in allContacts {
                    await presenter?.didReceive(contacts: contacts)
                }
            } catch {
                await presenter?.didReceive(error: error)
            }
        }
    }

    private func fetchPlayers() {
        Task { [weak presenter] in
            do {
                let votesOperation = repositoryVotes.fetchAllOperation(with: .init())
                let votes = try await votesOperation.asyncExecute()

                await presenter?.didReceive(players: votes)
            } catch {
                await presenter?.didReceive(error: error)
            }
        }
    }

    func addContact(for account: AccountId, username: String, imageData: Data?) {
        cancelContactRequest()

        fetchTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                guard let identifier = try await identifierService.fetch(for: account) else {
                    try Task.checkCancellation()
                    await presenter?.didReceive(error: ChatWithPlayersError.contactNotFound)
                    return
                }

                let ownKeyId = try await resolveOwnKey()

                try Task.checkCancellation()

                let remoteContact = Chat.RemoteContact(
                    accountId: account,
                    username: username,
                    chatPublicKey: identifier.localPublicKey,
                    imageData: imageData,
                    source: .game(gameIndex, gameDate)
                )

                try await chatRequestService.newOutgoingRequestFromText(
                    nil,
                    contact: remoteContact,
                    ownKeyId: ownKeyId,
                    ownPushToken: pushToken
                )

                try Task.checkCancellation()

                await presenter?.didReceive(remoteContact: remoteContact)
            } catch is CancellationError {
                // Do nothing
            } catch {
                await presenter?.didReceive(error: error)
            }
        }
    }

    func cancelContactRequest() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    func resolveOwnKey() async throws -> Chat.Contact.Own {
        guard let accountOrPerson = try await resolveAccountOrPerson() else {
            throw ChatWithPlayersError.noAccountOrPerson
        }

        switch accountOrPerson {
        case .account:
            logger.debug("Using candidate account")
            return try Chat.Contact.Own.gameCandidate()
        case .person:
            logger.debug("Using score alias account")
            return try Chat.Contact.Own.gameExternal()
        }
    }

    func resolveAccountOrPerson() async throws -> GamePallet.AccountOrPerson? {
        if let accountOrPerson = personDataStore.currentState?.makeAccountOrPerson() {
            return accountOrPerson
        }

        let personData = try await personDataStore.observe().first { $0?.makeAccountOrPerson() != nil }

        return personData??.makeAccountOrPerson()
    }
}
