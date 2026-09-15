import Foundation
import Operation_iOS
import Keystore_iOS
import CommonService
import AssetExchange
import KeyDerivation
import ChainRegistry
import EventCenter

protocol ProofOfInkFlowStateProtocol {
    var systemLocalDataFactory: SystemLocalDataFactoryProtocol { get }

    @discardableResult
    func setupBlockTimeService(
        for chainId: ChainModel.Id
    ) throws -> BlockTimeEstimationServiceProtocol

    func throttleBlockTimeService(for chainId: ChainModel.Id)

    func getBlockTimeOperationFactory(
        for chainId: ChainModel.Id
    ) throws -> BlockTimeOperationFactoryProtocol

    @discardableResult
    func setupTattooSelectionSyncService(
        for selectedWallet: WalletManaging,
        chain: ChainModel
    ) throws -> BaseObservableStateStore<TattooSelectionState>

    func throttleTattooSelectionSyncService()

    func applyOperationFactory(
        for selectedWallet: WalletManaging,
        chain: ChainModel
    ) throws -> TattooApplyOperationFactoryProtocol

    var candidateType: PersonRegistration.CandidateType? { get }
}

final class ProofOfInkFlowState {
    let chainRegistry: ChainRegistryProtocol
    let systemLocalDataFactory: SystemLocalDataFactoryProtocol
    let substrateStorageFacade: StorageFacadeProtocol
    let userStorageFacade: StorageFacadeProtocol
    let operationQueue: OperationQueue
    let eventCenter: EventCenterProtocol
    let logger: LoggerProtocol

    private var blockTimeServices: [ChainModel.Id: BlockTimeEstimationServiceProtocol] = [:]
    private var blockTimeOperationFactories: [ChainModel.Id: BlockTimeOperationFactoryProtocol] = [:]

    private var tattooSelectionSyncService: ApplicationServiceProtocol?
    private var tattooSelectionStateStore: BaseObservableStateStore<TattooSelectionState>?

    init(
        chainRegistry: ChainRegistryProtocol,
        substrateStorageFacade: StorageFacadeProtocol,
        userStorageFacade: StorageFacadeProtocol,
        eventCenter: EventCenterProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        systemLocalDataFactory = SystemLocalDataFactory(
            chainRegistry: chainRegistry,
            storageFacade: substrateStorageFacade,
            operationQueue: operationQueue,
            logger: logger
        )

        self.substrateStorageFacade = substrateStorageFacade
        self.userStorageFacade = userStorageFacade
        self.chainRegistry = chainRegistry
        self.eventCenter = eventCenter
        self.operationQueue = operationQueue
        self.logger = logger
    }

    deinit {
        throttleTattooSelectionSyncService()
        throttleAllBlockTimeServices()
    }

    private func throttleAllBlockTimeServices() {
        let keys = blockTimeServices.keys

        for key in keys {
            throttleBlockTimeService(for: key)
        }
    }
}

extension ProofOfInkFlowState: ProofOfInkFlowStateProtocol {
    @discardableResult
    func setupBlockTimeService(
        for chainId: ChainModel.Id
    ) throws -> BlockTimeEstimationServiceProtocol {
        if let blockTimeService = blockTimeServices[chainId] {
            return blockTimeService
        }

        let connection = try chainRegistry.getConnectionOrError(for: chainId)
        let runtimeService = try chainRegistry.getRuntimeProviderOrError(for: chainId)

        let repository = OnChainStorageRepositoryFactory(
            storageFacade: substrateStorageFacade
        ).createChainStorageItemRepository()

        let blockTimeService = BlockTimeEstimationService(
            chainId: chainId,
            connection: connection,
            runtimeService: runtimeService,
            repository: repository,
            operationQueue: operationQueue,
            logger: logger
        )

        blockTimeServices[chainId] = blockTimeService
        blockTimeService.setup()

        return blockTimeService
    }

    func throttleBlockTimeService(for chainId: ChainModel.Id) {
        blockTimeServices[chainId]?.throttle()
        blockTimeServices[chainId] = nil
    }

    func getBlockTimeOperationFactory(
        for chainId: ChainModel.Id
    ) throws -> BlockTimeOperationFactoryProtocol {
        if let blockTimeOperationFactory = blockTimeOperationFactories[chainId] {
            return blockTimeOperationFactory
        }

        guard let chain = chainRegistry.getChain(for: chainId) else {
            throw ChainRegistryError.noChain(chainId)
        }

        let factory = BlockTimeOperationFactory(chain: chain)
        blockTimeOperationFactories[chainId] = factory

        return factory
    }

    @discardableResult
    func setupTattooSelectionSyncService(
        for selectedWallet: WalletManaging,
        chain: ChainModel
    ) throws -> BaseObservableStateStore<TattooSelectionState> {
        if let tattooSelectionStateStore {
            return tattooSelectionStateStore
        }

        let connection = try chainRegistry.getConnectionOrError(for: chain.chainId)
        let provider = try chainRegistry.getRuntimeProviderOrError(for: chain.chainId)
        let selectedAccount = try selectedWallet.fetchAccount(for: chain)

        let store = TattooSelectionStateStore(logger: logger)

        let syncService = TattooSelectionSyncService(
            chainId: chain.chainId,
            accountId: selectedAccount.accountId,
            connection: connection,
            runtimeService: provider,
            observers: [store],
            operatonQueue: operationQueue,
            workQueue: .global(),
            logger: logger
        )

        tattooSelectionStateStore = store
        tattooSelectionSyncService = syncService

        syncService.setup()

        return store
    }

    func throttleTattooSelectionSyncService() {
        tattooSelectionSyncService?.throttle()
        tattooSelectionSyncService = nil

        tattooSelectionStateStore = nil
    }

    func applyOperationFactory(
        for selectedWallet: WalletManaging,
        chain: ChainModel
    ) throws -> TattooApplyOperationFactoryProtocol {
        let extrinsicServiceFactory = ExtrinsicServiceFactory(
            chainRegistry: chainRegistry,
            substrateStorageFacade: substrateStorageFacade,
            customFeeEstimator: ExtrinsicCustomFeeEstimatorFactory(providers: []),
            transactionExtensionFactory: CompoundTxExtensionFactory(),
            operationQueue: operationQueue
        )

        let extrinsicOriginFactory = ExtrinsicOriginFactory(
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            logger: logger
        )

        return TattooApplyOperationFactory(
            selectedWallet: selectedWallet,
            chain: chain,
            extrinsicServiceFactory: extrinsicServiceFactory,
            extrinsicOriginFactory: extrinsicOriginFactory,
            logger: logger
        )
    }

    var candidateType: PersonRegistration.CandidateType? {
        guard
            let tattooSelectionStateStore,
            let candidate = tattooSelectionStateStore.currentState?.candidate else {
            return nil
        }

        return PersonRegistration.CandidateType(candidate: candidate)
    }
}
