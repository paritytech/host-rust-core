import Coinage
import Foundation
import KeyDerivation
import Keystore_iOS
import FoundationExt
import SubstrateOperation
import ChainRegistry
import BackgroundExecution
import ExtrinsicService

extension ServiceCoordinator {
    struct CoinageServices {
        let coinageService: CoinageServicing
        let transferMonitor: CoinageTransferMonitoring
        let w3sPaymentTracking: W3sPaymentTracking
        let backupSyncService: CoinageBackupSyncServicing
        let claimStatusStore: ClaimStatusStore
    }

    static func createCoinageServices() -> CoinageServices? {
        let databaseFactory = CoinageDatabaseDependencyFactory(storageFacade: UserDataStorageFacade.shared)
        let claimStatusStore = ClaimStatusStore()

        let externalPaymentStore = ExternalPaymentCoreDataStore(
            storageFacade: UserDataStorageFacade.shared
        )

        guard let coinageService = createCoinageService(
            databaseFactory: databaseFactory,
            externalPaymentStore: externalPaymentStore
        ) else {
            return nil
        }

        let transferMonitor = CoinageTransferMonitor(
            coinageService: coinageService,
            storageFacade: UserDataStorageFacade.shared,
            claimStatusStore: claimStatusStore
        )

        let backupSyncService = CoinageBackupSyncService(
            coinageService: coinageService,
            coinRepository: databaseFactory.makeCoinRepository(),
            voucherRepository: databaseFactory.makeVoucherRepository()
        )

        return CoinageServices(
            coinageService: coinageService,
            transferMonitor: transferMonitor,
            w3sPaymentTracking: createW3sPaymentTracking(coinageService: coinageService),
            backupSyncService: backupSyncService,
            claimStatusStore: claimStatusStore
        )
    }

    private static func createW3sPaymentTracking(coinageService: CoinageServicing) -> W3sPaymentTracking {
        W3sPaymentTrackingService(
            historyStore: W3sPaymentHistoryCoreDataStore(
                storageFacade: UserDataStorageFacade.shared
            ),
            sendVerifier: coinageService.ongoingTransferService,
            blockInfoProvider: BlockInfoProvider(
                chainRegistry: ChainRegistryFacade.sharedRegistry,
                operationQueue: OperationManagerFacade.sharedDefaultQueue,
                chainId: AppConfig.Assets.mainAsset.chainId
            )
        )
    }
}

// MARK: - CoinageService Creation

private extension ServiceCoordinator {
    static func createCoinageService(
        databaseFactory: DatabaseDependencyFactoring,
        externalPaymentStore: ExternalPaymentStoring
    ) -> CoinageService? {
        let logger = Logger.shared
        let chainRegistry = ChainRegistryFacade.sharedRegistry
        let coinageChainId = AppConfig.Assets.mainAsset.chainId
        let operationQueue = OperationManagerFacade.sharedDefaultQueue

        guard let chain = chainRegistry.getChain(for: coinageChainId) else {
            logger.error("Failed to get chain for coinageChainId: \(coinageChainId)")
            return nil
        }

        let vrfRepo: BandersnatchManagerRepositoryProtocol = .shared

        guard
            let connection = chainRegistry.getConnection(for: coinageChainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: coinageChainId),
            let fullPersonKeyManager = try? vrfRepo.fullPerson(),
            let lightPersonKeyManager = try? vrfRepo.litePerson()
        else {
            logger.error("Failed to get connection/runtime/personhood keys for coinage")
            return nil
        }

        let voucherKeypairFactory = VoucherKeypairFactory(
            entropyManager: RootEntropyManager.shared
        )

        let consumedTokenChecker = ConsumedTokenChecker(
            operationQueue: operationQueue,
            connection: connection,
            runtimeCodingService: runtimeProvider
        )
        let viewFunctionFetcher = ViewFunctionFetcher(
            executor: ViewFunctionExecutor(
                chainRegistry: chainRegistry,
                operationQueue: operationQueue
            ),
            chainId: coinageChainId
        )
        let unloadTokenResolver = UnloadTokenResolver(
            runtimeCodingService: runtimeProvider,
            viewFunctionFetcher: viewFunctionFetcher,
            consumedTokenChecker: consumedTokenChecker
        )

        let coinageOriginFactory = CoinageOriginFactory(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            chain: chain,
            voucherKeyFactory: voucherKeypairFactory,
            fullPersonKeyManager: fullPersonKeyManager,
            lightPersonKeyManager: lightPersonKeyManager,
            unloadTokenResolver: unloadTokenResolver,
            connection: connection,
            runtimeCodingService: runtimeProvider,
            logger: logger
        )

        let extrinsicMonitorFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: SubstrateDataStorageFacade.shared,
            operationQueue: operationQueue
        )
        guard let monitorFactory = try? extrinsicMonitorFacade.createMonitorFactory(
            chain: chain
        ) else {
            logger.error("Failed to create extrinsic monitor factory")
            return nil
        }

        guard
            let extrinsicOperationFactory = try? extrinsicMonitorFacade.createOperationFactory(chain: chain),
            // Durability must observe the finalized outcome, not just inclusion, so the watch
            // follows each extrinsic until its block is finalized.
            let extrinsicSubmitter = try? extrinsicMonitorFacade.makeForkProtectedSubmitter(
                chain: chain,
                trackingTill: .finalized
            )
        else {
            logger.error("Failed to create extrinsic operation factory / submitter for coinage")
            return nil
        }

        let coinageTxStore = CoinageTxCoreDataRepository(
            storageFacade: UserDataStorageFacade.shared
        )

        return CoinageService.make(
            chainResource: chainRegistry,
            chain: chain,
            instanceId: AppConfig.Coinage.instanceId,
            databaseFactory: databaseFactory,
            originFactory: coinageOriginFactory,
            extrinsicMonitorFactory: monitorFactory,
            extrinsicOperationFactory: extrinsicOperationFactory,
            extrinsicSubmitter: extrinsicSubmitter,
            rootEntropyManager: RootEntropyManager.shared,
            keystore: Keychain(),
            txStore: coinageTxStore,
            applicationStateStreamFactory: ApplicationStateStreamFactory(),
            externalPaymentStore: externalPaymentStore,
            backgroundExecutor: ConnectionRetainingExecutor(provider: chainRegistry),
            recyclingStrategySettings: CoinageRecyclingStrategyStore.shared,
            personOriginProvider: coinageOriginFactory.personOriginProvider,
            viewFunctionFetcher: viewFunctionFetcher,
            logger: logger
        )
    }
}
