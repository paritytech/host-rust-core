import Foundation
import Keystore_iOS
import Operation_iOS
import SubstrateSdk
import Individuality
import CommonService
import KeyDerivation
import SubstrateOperation
import ChainRegistry

extension ServiceCoordinator {
    struct PersonhoodServices {
        let backgroundService: PersonhoodBackgroundService
        let registrationService: PersonhoodRegistrationServicing
    }

    static func createPersonhoodServices(
        syncStateStore: DetermineStateSyncStore
    ) -> PersonhoodServices? {
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard let vrfManager = try? vrfRepo.fullPerson(),
              let candidateAccountId = try? walletRepo.candidate().getRawPublicKey(),
              let chain = try? ChainRegistryFacade.sharedRegistry.getChainOrError(
                  for: AppConfig.Chains.usernameChain
              ) else {
            return nil
        }

        let operationFactory = PersonhoodRegistrationOperationFactory(
            accountId: candidateAccountId,
            vrfManager: vrfManager
        )

        let extrinsicSubmissionMonitor = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: ChainRegistryFacade.sharedRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: Logger.shared
        )

        let selfIncludeSubmissionService = PersonSelfIncludeSubmissionService(
            chain: chain,
            operationFactory: operationFactory,
            extrinsicSubmissionFacade: extrinsicSubmissionMonitor
        )

        guard
            let registrationService = try? createPersonhoodRegistrationService(
                chain: chain,
                walletRepo: walletRepo,
                vrfManager: vrfManager,
                operationFactory: operationFactory,
                selfIncludeSubmissionService: selfIncludeSubmissionService
            ),
            let backgroundService = createPersonRegistrationBackgroundService(),
            let selfIncludeBackgroundService = createPersonSelfIncludeBackgroundService(
                submitter: selfIncludeSubmissionService
            )
        else {
            return nil
        }

        let notificationService = PersonRegistrationNotificationService(
            localNotificationService: UserNotificationService.shared
        )

        let personhoodBackgroundService = PersonhoodBackgroundService(
            personhoodRegistrationService: registrationService,
            syncStateStore: syncStateStore,
            backgroundService: backgroundService,
            selfIncludeBackgroundService: selfIncludeBackgroundService,
            notificationService: notificationService
        )

        return PersonhoodServices(
            backgroundService: personhoodBackgroundService,
            registrationService: registrationService
        )
    }
}

private extension ServiceCoordinator {
    static func createPersonhoodRegistrationService(
        chain: ChainProtocol,
        walletRepo: WalletManagerRepositoryProtocol,
        vrfManager: BandersnatchKeyManaging,
        operationFactory: PersonhoodRegistrationOperationMaking,
        selfIncludeSubmissionService: SelfIncludeSubmitting
    ) throws -> PersonhoodRegistrationService {
        try PersonhoodRegistrationService(
            chain: chain,
            candidateWallet: walletRepo.candidate(),
            mobRuleWallet: walletRepo.mobRuleAlias(),
            scoreWallet: walletRepo.scoreAlias(),
            resourcesWallet: walletRepo.resourcesAlias(),
            vrfManager: vrfManager,
            blockNumberOperationFactory: BlockNumberOperationFactory(
                chainRegistry: ChainRegistryFacade.sharedRegistry,
                operationQueue: OperationManagerFacade.sharedDefaultQueue
            ),
            operationFactory: operationFactory,
            candidateOriginFactory: ExtrinsicOriginFactory.personCandidate(),
            personhoodOriginFactory: PersonhoodOriginFactory(
                vrfManager: vrfManager,
                chainRegistry: ChainRegistryFacade.sharedRegistry,
                operationQueue: OperationManagerFacade.sharedDefaultQueue,
                logger: Logger.shared
            ),
            selfIncludeSubmissionService: selfIncludeSubmissionService
        )
    }

    static func createPersonRegistrationBackgroundService() -> PersonRegistrationBackgroundServiceProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let walletRepo: WalletManagerRepositoryProtocol = .shared
        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
              let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.usernameChain),
              let vrfManager = try? vrfRepo.fullPerson(),
              let scoreWallet = try? walletRepo.scoreAlias() else {
            return nil
        }

        let logger = Logger.shared

        let connectionFactory = ConnectionFactory(
            apiKeysProvider: ConnectionApiKeysProvider.shared,
            logger: logger,
            operationQueue: OperationManagerFacade.runtimeSyncQueue,
            reachabilityManager: ReachabilityManager.shared
        )

        let queryFactory = PersonRegistrationQueryFactory(
            operationQueue: OperationManagerFacade.sharedDefaultQueue
        )

        let fetcher = PersonRegistrationStateFetcher(
            mobRuleWallet: walletRepo.mobRuleAlias(),
            scoreWallet: scoreWallet,
            resourcesWallet: walletRepo.resourcesAlias(),
            vrfManager: vrfManager,
            chain: chain,
            runtimeProvider: runtimeProvider,
            connectionFactory: connectionFactory,
            queryFactory: queryFactory,
            operationQueue: OperationManagerFacade.sharedDefaultQueue,
            logger: logger
        )

        return PersonRegistrationBackgroundService(
            fetcher: fetcher,
            logger: logger
        )
    }

    static func createPersonSelfIncludeBackgroundService(
        submitter: SelfIncludeSubmitting
    ) -> PersonSelfIncludeBackgroundServiceProtocol? {
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard
            let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: AppConfig.Chains.usernameChain),
            let vrfManager = try? vrfRepo.fullPerson()
        else {
            return nil
        }

        let connectionFactory = ConnectionFactory(
            apiKeysProvider: ConnectionApiKeysProvider.shared,
            logger: Logger.shared,
            operationQueue: OperationManagerFacade.runtimeSyncQueue,
            reachabilityManager: ReachabilityManager.shared
        )

        let fetcher = PersonSelfIncludeStateFetcher(
            vrfManager: vrfManager,
            chain: chain,
            runtimeProvider: runtimeProvider,
            connectionFactory: connectionFactory,
            logger: Logger.shared
        )

        return PersonSelfIncludeBackgroundService(
            fetcher: fetcher,
            submitter: submitter,
            logger: Logger.shared
        )
    }
}
