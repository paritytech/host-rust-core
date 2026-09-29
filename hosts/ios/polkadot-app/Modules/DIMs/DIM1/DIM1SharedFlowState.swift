import Foundation
import CommonService
import KeyDerivation
import ChainRegistry
import SubstrateSdk

protocol DIM1SharedFlowStateProtocol: AnyObject {
    var commonStateStore: DetermineStateSyncStore { get }
    var personStateStore: DetermineStatePersonDataStore { get }
    var gameInfoSyncService: GameInfoSyncServicing { get }
    var chainRegistry: ChainRegistryProtocol { get }
    var proofOfInkChainId: ChainModel.Id { get }
    var evidenceFileManagerFactory: EvidenceFileManagerFactoryProtocol { get }
    var proofOfInkFactory: ProofOfInkOperationFactoryProtocol { get }
    var evidenceSubmissionFactory: EvidenceLocalDataProviderFactoryProtocol { get }

    func createEvidenceSubmissionServices() -> DIM1EvidenceSubmissionFacadeProtocol
    func createEvidenceStateMediator(for fileManager: EvidenceFileManaging) -> ProvideEvidenceStateMediating
    func createGameTerminationService() throws -> GameTerminationServicing
    func createDIM1BackgroundService() -> DIM1BackgroundServiceProtocol?
}

class DIM1SharedFlowState {
    let commonStateStore: DetermineStateSyncStore
    let personStateStore: DetermineStatePersonDataStore
    let gameInfoSyncService: GameInfoSyncServicing
    let evidenceFileManagerFactory: EvidenceFileManagerFactoryProtocol
    let proofOfInkFactory: ProofOfInkOperationFactoryProtocol
    let evidenceSubmissionFactory: EvidenceLocalDataProviderFactoryProtocol

    let vrfManager: BandersnatchKeyManaging
    let candidateWallet: WalletManaging
    let proofOfInkChainId: ChainModel.Id
    let gameChainId: ChainModel.Id
    let mobRuleWallet: WalletManaging
    let scoreWallet: WalletManaging
    let resourcesWallet: WalletManaging
    let substrateStorageFacade: StorageFacadeProtocol
    let userStorageFacade: StorageFacadeProtocol
    let chainRegistry: ChainRegistryProtocol
    let operationQueue: OperationQueue
    let fileManager: FileManager
    let logger: LoggerProtocol

    init(
        commonStateStore: DetermineStateSyncStore,
        personStateStore: DetermineStatePersonDataStore,
        gameInfoSyncService: GameInfoSyncServicing,
        vrfManager: BandersnatchKeyManaging,
        candidateWallet: WalletManaging,
        mobRuleWallet: WalletManaging,
        scoreWallet: WalletManaging,
        resourcesWallet: WalletManaging,
        chainRegistry: ChainRegistryProtocol,
        proofOfInkChainId: ChainModel.Id,
        gameChainId: ChainModel.Id,
        userStorageFacade: StorageFacadeProtocol,
        substrateStorageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue,
        fileManager: FileManager,
        logger: LoggerProtocol
    ) {
        self.commonStateStore = commonStateStore
        self.personStateStore = personStateStore
        self.gameInfoSyncService = gameInfoSyncService
        self.vrfManager = vrfManager
        self.candidateWallet = candidateWallet
        self.mobRuleWallet = mobRuleWallet
        self.scoreWallet = scoreWallet
        self.resourcesWallet = resourcesWallet
        self.chainRegistry = chainRegistry
        self.proofOfInkChainId = proofOfInkChainId
        self.gameChainId = gameChainId
        self.userStorageFacade = userStorageFacade
        self.substrateStorageFacade = substrateStorageFacade
        self.operationQueue = operationQueue
        self.fileManager = fileManager
        self.logger = logger

        proofOfInkFactory = ProofOfInkOperationFactory(operationQueue: operationQueue)

        evidenceFileManagerFactory = EvidenceFileManagerFactory(fileManager: fileManager)

        evidenceSubmissionFactory = EvidenceLocalDataProviderFactory(
            repositoryFactory: EvidenceStateRepositoryFactory(substrateFacade: substrateStorageFacade),
            operationQueue: operationQueue,
            logger: logger
        )
    }
}

extension DIM1SharedFlowState: DIM1SharedFlowStateProtocol {
    func createEvidenceSubmissionServices() -> DIM1EvidenceSubmissionFacadeProtocol {
        let remoteServiceCoordinator = TattooUploadingServiceCoordinator(
            candidateWallet: candidateWallet,
            mobRuleWallet: mobRuleWallet,
            scoreWallet: scoreWallet,
            resourcesWallet: resourcesWallet,
            stateSyncObservers: [],
            chainRegistry: chainRegistry,
            operationQueue: operationQueue,
            processingQueue: .init(label: "io.polkadotapp.evidence.uploading.coordinator.queue"),
            logger: logger
        )

        let evidenceSubmissionRepositoryFactory = EvidenceStateRepositoryFactory(
            substrateFacade: substrateStorageFacade
        )

        let evidenceSubmissionLocalProviderFactory = EvidenceLocalDataProviderFactory(
            repositoryFactory: evidenceSubmissionRepositoryFactory,
            operationQueue: operationQueue,
            logger: logger
        )

        let evidenceSubmissionService = EvidenceSubmissionService(
            wallet: candidateWallet,
            extrinsicOriginFactory: ExtrinsicOriginFactory.personCandidate(),
            chainRegistry: chainRegistry,
            remoteStateStore: remoteServiceCoordinator.evidenceSubmissionStore,
            localStateProviderFactory: evidenceSubmissionLocalProviderFactory,
            repositoryFactory: evidenceSubmissionRepositoryFactory,
            userStorageFacade: userStorageFacade,
            substrateStorageFacade: substrateStorageFacade,
            fileManager: fileManager,
            evidenceFileManagerFactory: evidenceFileManagerFactory,
            operationQueue: operationQueue
        )

        return DIM1EvidenceSubmissionFacade(
            coordinator: remoteServiceCoordinator,
            submission: evidenceSubmissionService
        )
    }

    func createEvidenceStateMediator(for fileManager: EvidenceFileManaging) -> ProvideEvidenceStateMediating {
        ProvideEvidenceStateMediator(fileManager: fileManager)
    }

    func createDIM1BackgroundService() -> DIM1BackgroundServiceProtocol? {
        guard let chain = chainRegistry.getChain(for: proofOfInkChainId),
              let runtimeProvider = chainRegistry.getRuntimeProvider(for: proofOfInkChainId) else {
            logger.warning("No chain or runtime for background sync")
            return nil
        }

        let connectionFactory = ConnectionFactory(
            apiKeysProvider: ConnectionApiKeysProvider.shared,
            logger: logger,
            operationQueue: OperationManagerFacade.runtimeSyncQueue,
            reachabilityManager: ReachabilityManager.shared
        )

        let queryFactory = DIM1BackgroundQueryFactory(
            operationQueue: operationQueue
        )

        let fetcher = DIM1BackgroundStateFetcher(
            candidateWallet: candidateWallet,
            chain: chain,
            runtimeProvider: runtimeProvider,
            connectionFactory: connectionFactory,
            queryFactory: queryFactory,
            operationQueue: operationQueue,
            logger: logger
        )

        return DIM1BackgroundService(
            fetcher: fetcher,
            logger: logger
        )
    }

    func createGameTerminationService() throws -> GameTerminationServicing {
        let chain = try chainRegistry.getChainOrError(for: gameChainId)

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: substrateStorageFacade,
            operationQueue: operationQueue
        )

        let extrinsicSubmissionMonitor = try extrinsicSubmissionFacade.createMonitorFactory(chain: chain)

        return GameTerminationService(
            extrinsicOriginFactory: ExtrinsicOriginFactory.personCandidate(),
            extrinsicMonitoring: extrinsicSubmissionMonitor,
            wallet: candidateWallet,
            chain: chain
        )
    }
}
