import Foundation
import FoundationExt
import EventKit
import SubstrateSdk
import SubstrateStateCall
import AssetExchange
import Keystore_iOS
import KeyDerivation
import ChainRegistry
import BackgroundExecution
import UIKit.UIApplication

enum WeeklyGameFactory {
    @MainActor
    static func create(
        settings: ChatExtensionBotSettings,
        dependencies: DIM2Depending,
        personActions: [ChatExtensionActions.ActionModel]
    ) -> DIM2ChatExtension? {
        guard let interactor = createInteractor(dependencies: dependencies) else {
            Logger.shared.error("Failed to create DIM2ChatInteractor")
            return nil
        }

        let wireframe = WeeklyGameWireframe(
            assetId: AppConfig.Assets.dimAsset,
            notificationService: UserNotificationService.shared,
            application: UIApplication.shared
        )

        return DIM2ChatExtension(
            settings: settings,
            interactor: interactor,
            wireframe: wireframe,
            cameraPermissionService: CameraPermissionService(),
            applicationStateStreamFactory: ApplicationStateStreamFactory(),
            personActions: personActions,
            logger: Logger.shared
        )
    }

    @MainActor
    private static func createInteractor(dependencies: DIM2Depending) -> DIM2ChatInteractor? {
        let logger = Logger.shared
        let operationQueue = OperationManagerFacade.sharedDefaultQueue
        let dim2FlowState = dependencies.sharedState
        let chainId = dim2FlowState.chainId

        guard
            let chain = dim2FlowState.chainRegistry.getChain(for: chainId),
            let connection = dim2FlowState.chainRegistry.getConnection(for: chainId),
            let runtimeProvider = dim2FlowState.chainRegistry.getRuntimeProvider(for: chainId),
            let gameRegisterService = try? dim2FlowState.setupGameRegistrationService()
        else {
            logger.error("Missing chain dependencies for DIM2ChatInteractor")
            return nil
        }

        let invitationRegistrationService = makeInvitationRegistrationService(
            chain: chain,
            candidateWallet: dim2FlowState.candidateWallet,
            chainRegistry: dim2FlowState.chainRegistry,
            chainId: chainId,
            gameRegisterService: gameRegisterService,
            operationQueue: operationQueue,
            logger: logger
        )

        // Balance operation factory
        let extrinsicServiceFactory = ExtrinsicServiceFactory(
            chainRegistry: dim2FlowState.chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            customFeeEstimator: ExtrinsicCustomFeeEstimatorFactory(providers: []),
            transactionExtensionFactory: CompoundTxExtensionFactory(),
            operationQueue: operationQueue,
            logger: logger
        )

        let requiredBalanceOperationFactory = GamePalletBalanceOperationFactory(
            extrinsicServiceFactory: extrinsicServiceFactory,
            extrinsicOriginFactory: ExtrinsicOriginFactory.personCandidate(),
            stateCallFactory: StateCallRequestFactory(),
            wallet: dim2FlowState.candidateWallet,
            chain: chain,
            connection: connection,
            runtimeProvider: runtimeProvider
        )

        let remainingGamesOperationFactory = RemainingGamesOperationFactory(
            connection: connection,
            runtimeService: runtimeProvider
        )

        let userNotificationService = UserNotificationService.shared

        // Notification service
        let gameNotificationsService = GameNotificationService(
            localNotificationService: userNotificationService,
            gameStartReminder: dim2FlowState.gameStartReminder
        )

        // Calendar service
        let gameCalendarService = GameCalendarService(eventStore: EKEventStore())

        return DIM2ChatInteractor(
            dependencies: dependencies,
            gameVoteRepositoryFactory: GameVoteRepositoryFactory(),
            gameCalendarService: gameCalendarService,
            gameNotificationsService: gameNotificationsService,
            invitationRegistrationService: invitationRegistrationService,
            balanceTrackingFactory: BalanceTrackingFactory(),
            requiredBalanceOperationFactory: requiredBalanceOperationFactory,
            remainingGamesOperationFactory: remainingGamesOperationFactory,
            backgroundExecutor: ConnectionRetainingExecutor(provider: dim2FlowState.chainRegistry),
            localNetworkPermissionService: LocalNetworkPermissionService.shared,
            logger: logger
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func makeInvitationRegistrationService(
        chain: ChainModel,
        candidateWallet: WalletManaging,
        chainRegistry: ChainRegistryProtocol,
        chainId: ChainModel.Id,
        gameRegisterService: GameRegisterServicing,
        operationQueue: OperationQueue,
        logger: Logger
    ) -> GameInvitationRegistrationService {
        let invitationService = InvitationIssuanceService(
            chain: chain,
            candidate: candidateWallet,
            tokenProvider: JWTTokenManager.shared
        )

        let observerFactory = PendingInvitationObserverFactory(
            chainId: chainId,
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )

        return GameInvitationRegistrationService(
            invitationFactory: invitationService,
            invitationStorage: InvitationStorageService(),
            observerFactory: observerFactory,
            gameRegisterService: gameRegisterService,
            logger: logger
        )
    }
}
