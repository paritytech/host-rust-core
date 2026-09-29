import Foundation
import SubstrateSdk
import Keystore_iOS
import KeyDerivation
import MessageExchangeKit
import StatementStore
import Products
@preconcurrency import WebRTC

@MainActor
enum GameVideoViewFactory {
    static func createView(
        serviceCoordinator: ServiceCoordinatorProtocol,
        intendedGameId: Game.Identifier? = nil,
        flowState: SPAFlowState
    ) -> GameVideoViewProtocol? {
        let extensionId = DIM2ChatExtension.identifier

        guard let dim2Extension = serviceCoordinator
            .chatExtensionsRegistry
            .getChatExtensionBot(for: extensionId) as? DIM2ChatExtending
        else {
            return nil
        }

        return createView(
            flowState: dim2Extension.flowState,
            chatId: .chatExtension(extensionId),
            turnService: serviceCoordinator.turnService,
            intendedGameId: intendedGameId,
            spaFlowState: flowState
        )
    }

    static func createView(
        flowState: DIM2SharedFlowStateProtocol,
        chatId: Chat.Id,
        turnService: TURNCredentialsProviding,
        intendedGameId: Game.Identifier? = nil,
        spaFlowState: SPAFlowState
    ) -> GameVideoViewProtocol? {
        let peerConnectionFactory = WebRTCPeerConnectionFactoryProvider.make()
        let rtcClient = RTCClient(
            peerConnectionFactory: peerConnectionFactory,
            isAudioEnabled: false,
            videoProfile: .game
        )

        guard let interactor = createInteractor(
            flowState: flowState,
            rtcClient: rtcClient,
            turnService: turnService,
            intendedGameId: intendedGameId
        ) else {
            return nil
        }

        let wireframe = GameVideoWireframe(
            flowState: flowState,
            chatId: chatId,
            spaFlowState: spaFlowState
        )

        let presenter = GameVideoPresenter(
            interactor: interactor,
            wireframe: wireframe,
            rtcClient: rtcClient,
            cameraPermissionService: CameraPermissionService(),
            viewModelFactory: GameVideoViewModelFactory(
                accountId: interactor.accountId
            )
        )

        let view = GameVideoViewController(presenter: presenter)

        presenter.view = view
        interactor.presenter = presenter

        return view
    }

    private static func createInteractor(
        flowState: DIM2SharedFlowStateProtocol,
        rtcClient: RTCClient,
        turnService: TURNCredentialsProviding,
        intendedGameId: Game.Identifier?
    ) -> GameVideoInteractor? {
        let chainRegistry = flowState.chainRegistry
        let logger = Logger.shared

        guard let chain = chainRegistry.getChain(for: flowState.chainId) else {
            return nil
        }

        guard let account = GameAccountFactory.makeAccount(
            chain: chain,
            registeredSource: flowState.source
        ) else {
            return nil
        }

        guard let gameSignKeyId = try? GameAccountFactory.makeWalletKeyId(for: flowState.source) else {
            return nil
        }

        let workQueue = DispatchQueue(label: "GameVideoModule.workQueue")

        // Create new MessageExchangeKit-based dependencies.
        // Each peer gets its own factory (and work queue) to avoid serial queue
        // contention when multiple peers connect concurrently.
        let serviceFactoryProvider: () -> MessageExchageServiceMaking = {
            MessageExchangeServiceFactory(
                messageExchangeModeProvider: FixedMessageExchangeModeProvider(mode: .identity),
                entropyManager: RootEntropyManager.shared,
                deviceEncryptionKeyFactory: nil,
                messageRouteSelector: { _ in .identity },
                maxStatementSize: MessageExchangeCoordinatorFactory.Constants.maxChatStatementSize,
                logger: logger
            )
        }

        let identifierService = ChatIdentifierService(
            chainRegistry: chainRegistry,
            chain: AppConfig.Chains.chatChain,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: logger
        )

        let sessionFactory = VideoGameSessionFactory(
            ownSignKeyId: gameSignKeyId,
            serviceFactoryProvider: serviceFactoryProvider,
            identifierService: identifierService,
            chainRegistry: chainRegistry
        )

        let attemptTracker = ConnectionAttemptTracker()

        let peerEngineContextFactory = VideoGamePeerEngineContextFactory(
            localAccountId: account.accountId,
            sessionFactory: sessionFactory,
            attemptTracker: attemptTracker,
            turnService: turnService
        )

        let connectionManager = VideoGameConnectionManager(
            localAccountId: account.accountId,
            contextFactory: peerEngineContextFactory,
            callbackQueue: workQueue,
            logger: logger
        )

        let stateMachine = GameStateMachine(
            workQueue: workQueue,
            infoSyncService: flowState.gameSyncService,
            timelineService: GameTimelineService(
                workQueue: workQueue,
                infoSyncService: flowState.gameSyncService,
                synchronizedTimeService: SynchronizedTimeService()
            )
        )

        let gameVideoService = GameVideoService(
            accountId: account.accountId,
            workQueue: workQueue,
            connectionManager: connectionManager,
            rtcClient: rtcClient,
            stateMachine: stateMachine,
            gameSyncService: flowState.gameSyncService,
            gameDashboardTelemetry: flowState.gameDashboardTelemetry
        )

        let settingsManager = SettingsManager.shared

        let interactor = GameVideoInteractor(
            accountId: account.accountId,
            gameVideoService: gameVideoService,
            infoSyncService: flowState.gameSyncService,
            intendedGameId: intendedGameId,
            gameStartReminder: flowState.gameStartReminder,
            application: .shared,
            settingsManager: settingsManager,
            workQueue: workQueue
        )

        gameVideoService.delegate = interactor

        return interactor
    }
}
