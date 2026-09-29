import Foundation
import MessageExchangeKit
import StatementStore
import SubstrateSdk
import NovaCrypto
import Keystore_iOS
import SDKLogger
import KeyDerivation
import ChainRegistry

protocol ChatRequestServiceMaking {
    func makeDiscoveryService() async throws -> ChatDiscoveryServicing

    func makeIncomingChatRequestService() async throws -> IncomingChatRequestServicing

    func makeOutgoingChatRequestService() async throws -> OutgoingChatRequestServicing

    func makeIncomingChatRequestContext() async throws -> IncomingChatRequestCoordinationContext

    func makeOutgoingChatRequestContext() async throws -> OutgoingChatRequestCoordinationContext
}

actor ChatRequestServiceFactory {
    let chatChainId: ChainModel.Id
    let entropyManager: RootEntropyManaging
    let chainRegistry: ChainRegistryProtocol
    let storageFacade: StorageFacadeProtocol
    let discoverySettings: ChatDiscoverySettingsStoring
    let operationQueue: OperationQueue
    let logger: LoggerProtocol
    let remoteContactResolver: RemoteContactResolving

    private var connection: StatementStoreConnecting?
    private var accountSignManager: StatementStoreSignerManaging?
    private var accountEncryptionManager: MessageExchangeEncryptionManaging?

    init(
        remoteContactResolver: RemoteContactResolving,
        chatChainId: ChainModel.Id = AppConfig.Chains.chatChain,
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        entropyManager: RootEntropyManaging = RootEntropyManager.shared,
        storageFacade: StorageFacadeProtocol = UserDataStorageFacade.shared,
        discoverySettings: ChatDiscoverySettingsStoring = SettingsManager.shared,
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: SDKLoggerProtocol = Logger.shared
    ) {
        self.remoteContactResolver = remoteContactResolver
        self.chatChainId = chatChainId
        self.chainRegistry = chainRegistry
        self.entropyManager = entropyManager
        self.storageFacade = storageFacade
        self.discoverySettings = discoverySettings
        self.operationQueue = operationQueue
        self.logger = logger
    }
}

extension ChatRequestServiceFactory: ChatRequestServiceMaking {
    func makeDiscoveryService() async throws -> ChatDiscoveryServicing {
        let connection = try await makeConnection()
        let signManager = makeAccountSignManager()
        let encryptionManager = makeAccountEncryptionManager()

        let chatRequestFactory = ChatRequestFactory(
            encryptionManager: encryptionManager,
            signManager: signManager,
            remoteContactResolver: remoteContactResolver
        )

        return ChatDiscoveryService(
            signManager: signManager,
            settings: discoverySettings,
            statementStoreConnection: connection,
            chatRequestFactory: chatRequestFactory,
            logger: logger
        )
    }

    func makeIncomingChatRequestService() async throws -> IncomingChatRequestServicing {
        let connection = try await makeConnection()
        let encryptionManager = makeAccountEncryptionManager()
        let signManager = makeAccountSignManager()

        let channelFactory = ChatRequestChannelFactory(
            encryptionManager: encryptionManager,
            signingManager: signManager,
            sessionIdFactory: PeerSessionIdFactory()
        )

        let chatRequestFactory = ChatRequestFactory(
            encryptionManager: encryptionManager,
            signManager: signManager,
            remoteContactResolver: remoteContactResolver
        )

        return IncomingChatRequestService(
            statementStoreConnection: connection,
            channelFactory: channelFactory,
            chatRequestFactory: chatRequestFactory,
            logger: logger
        )
    }

    func makeOutgoingChatRequestService() async throws -> OutgoingChatRequestServicing {
        // TODO: Implement alias signer when available
        let aliasSignManager = makeAccountSignManager()

        let connection = try await makeConnection()
        let encryptionManager = makeAccountEncryptionManager()
        let accountSignManager = makeAccountSignManager()

        let channelFactory = ChatRequestChannelFactory(
            encryptionManager: encryptionManager,
            signingManager: accountSignManager,
            sessionIdFactory: PeerSessionIdFactory()
        )

        let chatRequestFactory = ChatRequestFactory(
            encryptionManager: encryptionManager,
            signManager: accountSignManager,
            remoteContactResolver: remoteContactResolver
        )

        return OutgoingChatRequestService(
            statementStoreSubmitter: connection,
            statementSignManager: aliasSignManager,
            requestFactory: chatRequestFactory,
            priorityFactory: StatementPriorityFactory(),
            channelFactory: channelFactory,
            logger: logger
        )
    }

    func makeIncomingChatRequestContext() async throws -> IncomingChatRequestCoordinationContext {
        let encryptionManager = makeAccountEncryptionManager()
        let signManager = makeAccountSignManager()
        let messageExchangeModeProvider = try ChatMessageExchangeModeProvider(
            tld: DotNsTldProviderFacade.shared.currentTldOrError()
        )

        return try IncomingChatRequestCoordinationContext(
            discoveryOwnKeyIds: [Chat.Contact.Own.main()],
            matchOwnKeyIds: Chat.Contact.Own.allPossibleIds(),
            requestStoreService: ChatRequestStoreService(
                messageExchangeModeProvider: messageExchangeModeProvider,
                storageFacade: storageFacade,
                pushIdFactory: ChatPushIdFactory(
                    encryptionManager: encryptionManager,
                    signManager: signManager,
                    sessionIdFactory: PeerSessionIdFactory(),
                    logger: logger
                ),
                deviceEncryptionKeyManager: DeviceEncryptionKeyManager.shared,
            ),
            messageExchangeModeProvider: messageExchangeModeProvider,
            contactsStorageService: ContactsLocalStorageService(),
            remoteContactResolver: remoteContactResolver
        )
    }

    func makeOutgoingChatRequestContext() async throws -> OutgoingChatRequestCoordinationContext {
        let messageStoreService = MessagesLocalStorageService(
            repositoryFactory: ChatMessageRepositoryFactory(storageFacade: storageFacade),
            statusUpdateRepositoryFactory: ChatMessageStatusUpdateRepositoryFactory(storageFacade: storageFacade),
            logger: logger
        )

        return OutgoingChatRequestCoordinationContext(
            messageStoreService: messageStoreService,
            logger: logger
        )
    }
}

private extension ChatRequestServiceFactory {
    func makeConnection() async throws -> StatementStoreConnecting {
        if let connection {
            return connection
        }

        let chainConnection = try chainRegistry.getConnectionOrError(for: chatChainId)

        let connection = StatementStoreConnection(
            connection: chainConnection,
            retryMatcher: StatementSubmitErrorMatcher.retryWhenTimeoutOrNoAllowance(),
            logger: logger
        )

        self.connection = connection

        return connection
    }

    func makeAccountEncryptionManager() -> MessageExchangeEncryptionManaging {
        if let accountEncryptionManager {
            return accountEncryptionManager
        }

        let manager = ChatEncryptionManager(entropyManager: entropyManager)

        accountEncryptionManager = manager

        return manager
    }

    func makeAccountSignManager() -> StatementStoreSignerManaging {
        if let accountSignManager {
            return accountSignManager
        }

        let manager = ChatSignerManager(entropyManager: entropyManager)

        accountSignManager = manager

        return manager
    }
}
