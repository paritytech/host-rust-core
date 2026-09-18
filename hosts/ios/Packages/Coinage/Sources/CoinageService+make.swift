import Foundation
import ExtrinsicService
import KeyDerivation
import Keystore_iOS
import NovaCrypto
import Operation_iOS
import SDKLogger
import ChainStore
import SubstrateSdk
import SubstrateStorageQuery
import SubstrateOperation
import FoundationExt
import BackgroundExecution
import Individuality
import DurableTransactions

public extension CoinageService {
    /// Creates a CoinageService instance.
    ///
    /// - Parameters:
    ///   - chainResource: Chain resource for RPC connections
    ///   - chain: The chain configuration
    ///   - instanceId: Coinage pallet instance the app operates on (from remote config)
    ///   - databaseFactory: Factory for creating database repositories
    ///   - originFactory: Factory for creating extrinsic origins (app-side implementation)
    ///   - extrinsicMonitorFactory: Factory for extrinsic submission monitoring
    ///   - durableEngine: The shared durable transaction engine; coinage registers its oracle with it
    ///   - chainViewFactory: Pinned chain views for reads outside the engine
    ///   - assetLedger: Coinage's half of the ledger (asset rows, handoff marks)
    ///   - rootEntropyManager: Manager for root entropy (key derivation)
    ///   - keystore: Keystore for key management
    ///   - logger: Logger for diagnostic output
    ///   - schedulerFactory: Coin recycling background task scheduler
    /// - Returns: A configured CoinageServicing instance
    // swiftlint:disable:next function_body_length
    static func make(
        chainResource: ChainResourceProtocol,
        chain: ChainProtocol,
        instanceId: CoinageInstanceId,
        databaseFactory: DatabaseDependencyFactoring,
        originFactory: OriginCreating,
        extrinsicMonitorFactory: ExtrinsicSubmitMonitorFactoryProtocol,
        durableEngine: any DurableTxServicing,
        chainViewFactory: any PinnedChainViewFactoryProtocol,
        assetLedger: any CoinageAssetLedgerProtocol,
        rootEntropyManager: RootEntropyManaging,
        keystore: KeystoreProtocol,
        applicationStateStreamFactory: ApplicationStateStreamFactory,
        externalPaymentStore: ExternalPaymentStoring,
        incomingPaymentStore: IncomingPaymentStoring,
        incomingPaymentSecretStore: IncomingPaymentSecretStoring,
        incomingPaymentAcknowledger: IncomingPaymentAcknowledging,
        backgroundExecutor: any BackgroundExecuting,
        recyclingStrategySettings: any CoinageRecyclingStrategyProviding,
        personOriginProvider: any OriginPersonProviding,
        viewFunctionFetcher: any ViewFunctionFetching,
        logger: SDKLoggerProtocol
    ) -> CoinageService {
        let operationQueue = OperationQueue()

        guard let connection = chainResource.getRpcConnection(for: chain.chainId) else {
            fatalError("Failed to get RPC connection for chain \(chain.chainId)")
        }
        guard let runtimeService = chainResource.getRuntimeCodingService(for: chain.chainId) else {
            fatalError("Failed to get runtime service for chain \(chain.chainId)")
        }

        let coinRepository = databaseFactory.makeCoinRepository()
        let trackedVoucherRepository = databaseFactory.makeTrackedVoucherRepository()
        let voucherRepository = databaseFactory.makeVoucherRepository()

        let voucherIndexstore = VoucherIndexstore(storage: keystore)
        let coinsIndexstore = CoinIndexstore(storage: keystore)
        let coinKeypairFactory = CoinKeypairFactory(entropyManager: rootEntropyManager)
        let voucherKeypairFactory = VoucherKeypairFactory(entropyManager: rootEntropyManager)
        // One allocator per Coinage instance: actor isolation serialises the index counter only
        // within a single instance.
        let coinAllocator = CoinAllocator(
            storage: coinsIndexstore,
            coinRepository: coinRepository,
            keyFactory: coinKeypairFactory
        )
        let voucherAllocator = VoucherAllocator(
            storage: voucherIndexstore,
            delayProvider: VoucherDelayProvider(),
            voucherRepository: voucherRepository,
            keyFactory: voucherKeypairFactory
        )

        // One minter per Coinage instance wraps both allocators; every mint site goes through it.
        let coinageMinter = CoinageMinter(coinAllocator: coinAllocator, voucherAllocator: voucherAllocator)

        let coinService = CoinService(databaseFactory: databaseFactory)

        let storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        let contextLoader = DenominationContextLoader(
            instanceId: instanceId,
            connection: connection,
            storageRequestFactory: storageRequestFactory,
            runtimeService: runtimeService
        )

        let readinessLoader = RecyclerReadinessLoader(
            instanceId: instanceId,
            connection: connection,
            runtimeCodingService: runtimeService,
            operationQueue: operationQueue
        )

        let coinSelector = CoinSelector()

        let blockNumberProvider = BlockInfoProvider(
            chainRegistry: chainResource,
            operationQueue: operationQueue,
            chainId: chain.chainId
        )

        let coinOnChainQuery = CoinOnChainQueryService(
            connection: connection,
            runtimeService: runtimeService,
            storageRequestFactory: storageRequestFactory
        )

        let voucherOnChainQuery = VoucherOnChainQueryService(
            instanceId: instanceId,
            connection: connection,
            runtimeService: runtimeService,
            storageRequestFactory: storageRequestFactory,
            publicKeyProvider: { try voucherKeypairFactory.derivePublicKey(index: $0) },
            aliasProvider: { try voucherKeypairFactory.alias(for: $0) }
        )

        // Coinage's oracle answers the engine's two questions from its asset rows and its own chain
        // reads; the engine owns the ledger row, the submission watch and recovery.
        let stateReader = CoinageStateReader(coinQuery: coinOnChainQuery, voucherQuery: voucherOnChainQuery)
        durableEngine.oracles.register(
            CoinageResourceOracle(chainId: chain.chainId, ledger: assetLedger, reader: stateReader),
            for: .coinage
        )

        let txService = CoinageTxService(engine: durableEngine, ledger: assetLedger, logger: logger)

        let voucherLoaderFactory = VoucherLoaderFactory(
            instanceId: instanceId,
            minter: coinageMinter,
            keypairFactory: voucherKeypairFactory,
            txService: txService,
            originCreating: originFactory,
            runtimeService: runtimeService,
            chain: chain,
            logger: logger
        )
        let voucherService = VoucherService(
            databaseFactory: databaseFactory,
            trackedVoucherRepository: trackedVoucherRepository,
            voucherLoaderFactory: voucherLoaderFactory
        )

        let consumedTokenChecker = ConsumedTokenChecker(
            operationQueue: operationQueue,
            connection: connection,
            runtimeCodingService: runtimeService
        )
        let quotaTracker = UnloadQuotaTracker(
            runtimeCodingService: runtimeService,
            consumedTokenChecker: consumedTokenChecker,
            personOriginProvider: personOriginProvider,
            viewFunctionFetcher: viewFunctionFetcher
        )

        let planFactory = TransferPlanFactory(
            instanceId: instanceId,
            minter: coinageMinter,
            voucherKeyFactory: voucherKeypairFactory,
            coinKeyFactory: coinKeypairFactory,
            durability: txService,
            originFactory: originFactory,
            quotaTracker: quotaTracker,
            recyclerLoader: readinessLoader,
            blockInfoProvider: blockNumberProvider,
            logger: logger
        )

        let memoBuilder = MemoBuilder(
            privateKeyDeriver: coinKeypairFactory
        )

        let senderService = TransferSenderService(
            coinSelector: coinSelector,
            planFactory: planFactory,
            memoBuilder: memoBuilder,
            recyclerLoader: readinessLoader,
            logger: logger
        )

        let recoveryService = CoinageBackupRecoveryService(
            coinIndexstore: coinsIndexstore,
            voucherIndexstore: voucherIndexstore,
            coinKeypairFactory: coinKeypairFactory,
            coinOnChainQuery: coinOnChainQuery,
            voucherOnChainQuery: voucherOnChainQuery,
            logger: logger
        )

        let transferSubmitter = CoinTransferSubmitter(
            originFactory: originFactory,
            extrinsicMonitor: extrinsicMonitorFactory
        )

        let claimSubmitter = CoinageClaimSubmitter(
            minter: coinageMinter,
            originFactory: originFactory,
            txService: txService,
            logger: logger
        )

        let claimCoinsService = ClaimCoinsService(
            txService: txService,
            coinOnChainQuery: coinOnChainQuery,
            claimSubmitter: claimSubmitter,
            snKeyFactory: SNKeyFactory(),
            coinService: coinService,
            logger: logger
        )

        let recipientService = TransferRecipientService(
            coinMinter: coinageMinter,
            coinKeyFactory: coinKeypairFactory,
            coinService: coinService,
            coinOnChainQuery: coinOnChainQuery,
            transferSubmitter: transferSubmitter,
            snKeyFactory: SNKeyFactory(),
            claimCoinsService: claimCoinsService,
            blockNumberProvider: blockNumberProvider,
            logger: logger
        )

        let coinStateSyncService = CoinStateSyncService(
            coinService: coinService,
            databaseFactory: databaseFactory,
            connection: connection,
            runtimeService: runtimeService,
            logger: logger
        )

        let ringCapacityProvider = RingCapacityProvider(
            instanceId: instanceId,
            operationQueue: operationQueue,
            connection: connection,
            runtimeCodingService: runtimeService
        )

        let voucherLocationService = VoucherLocationService(
            instanceId: instanceId,
            voucherRepository: voucherRepository,
            databaseFactory: databaseFactory,
            connection: connection,
            runtimeService: runtimeService,
            ringCapacityProvider: ringCapacityProvider,
            logger: logger
        )

        let recyclingService = CoinageRecyclingService(
            voucherMinter: coinageMinter,
            coinKeypairFactory: coinKeypairFactory,
            voucherKeypairFactory: voucherKeypairFactory,
            txService: txService,
            voucherService: voucherService,
            originFactory: originFactory,
            backgroundExecutor: backgroundExecutor,
            logger: logger
        )

        let recyclingStrategyResolver = RecyclingStrategyProvider(quotaTracker: quotaTracker)
        let preClassificator = CoinageAssetPreClassificator()

        let externalPaymentDependency = ExternalPaymentDependency(
            instanceId: instanceId,
            coinService: coinService,
            voucherService: voucherService,
            assetClassifier: ExternalPaymentAssetClassifier(
                settings: recyclingStrategySettings,
                strategyResolver: recyclingStrategyResolver,
                ringCapacityProvider: ringCapacityProvider,
                preClassificator: preClassificator,
                logger: logger
            ),
            recycler: recyclingService,
            voucherKeyFactory: voucherKeypairFactory,
            voucherMinter: coinageMinter,
            recyclerLoader: readinessLoader,
            extrinsicMonitor: extrinsicMonitorFactory,
            durability: txService,
            originFactory: originFactory,
            quotaTracker: quotaTracker,
            blockNumberProvider: blockNumberProvider
        )

        let externalPaymentService = ExternalPaymentService(
            store: externalPaymentStore,
            dependency: externalPaymentDependency,
            logger: logger
        )

        let transferStatusService = CoinageTransferStatusService(
            databaseFactory: databaseFactory,
            chainViewFactory: chainViewFactory,
            chainId: chain.chainId,
            coinOnChainQuery: coinOnChainQuery,
            snKeyFactory: SNKeyFactory(),
            logger: logger
        )

        let assetsTracking = AssetBalanceTracker(
            connection: connection,
            runtimeService: runtimeService,
            storageRequestFactory: storageRequestFactory,
            logger: logger
        )

        let claimAssetService = ClaimAssetService(
            assetsTracking: assetsTracking,
            voucherLoaderFactory: voucherLoaderFactory,
            voucherService: voucherService,
            txService: txService,
            logger: logger
        )

        let incomingPaymentSourceResolver = IncomingPaymentSourceResolver(
            entropyManager: rootEntropyManager,
            snKeyFactory: SNKeyFactory()
        )

        let incomingPaymentService = IncomingPaymentService(
            store: incomingPaymentStore,
            secretStore: incomingPaymentSecretStore,
            sourceResolver: incomingPaymentSourceResolver,
            paymentContext: IncomingPaymentContext(logger: logger),
            claimCoinsService: claimCoinsService,
            claimAssetService: claimAssetService,
            verdictResolver: CoinageGroupVerdictResolver(
                txService: txService,
                coinService: coinService,
                voucherService: voucherService
            ),
            acknowledger: incomingPaymentAcknowledger,
            instanceId: instanceId,
            logger: logger
        )

        let coinageService = CoinageService(
            coinService: coinService,
            voucherService: voucherService,
            coinKeypairFactory: coinKeypairFactory,
            senderService: senderService,
            ongoingTransferService: recipientService,
            txService: txService,
            claimCoinsService: claimCoinsService,
            transferStatusService: transferStatusService,
            externalPaymentService: externalPaymentService,
            contextLoader: contextLoader,
            coinStateSyncService: coinStateSyncService,
            voucherLocationService: voucherLocationService,
            recyclingService: recyclingService,
            recyclingStrategySettings: recyclingStrategySettings,
            recyclingStrategyResolver: recyclingStrategyResolver,
            ringCapacityProvider: ringCapacityProvider,
            preClassificator: preClassificator,
            applicationStateStreamFactory: applicationStateStreamFactory,
            databaseFactory: databaseFactory,
            recoveryService: recoveryService,
            incomingPaymentService: incomingPaymentService,
            logger: logger
        )

        return coinageService
    }
}

extension VoucherKeyDeriving {
    func alias(for index: DerivationIndex) throws -> Data {
        try createKeyManager(index: index)
            .deriveAlias(for: UnloadTokenContextBuilder.recyclerAliasContext)
    }
}
