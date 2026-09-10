import Foundation
import SubstrateSdk
import MessageExchangeKit
import KeyDerivation
import Individuality
import ChainRegistry

protocol DIM2SharedFlowStateProtocol: AnyObject {
    var source: People.RegisteredSource? { get }

    var candidateWallet: WalletManaging { get }
    var score: WalletManaging { get }
    var vrfManager: BandersnatchKeyManaging { get }
    var chatEncryptionManager: MessageExchangeEncryptionMaking { get }
    var chainRegistry: ChainRegistryProtocol { get }
    var chainId: ChainModel.Id { get }

    var gameSyncService: GameInfoSyncServicing { get }
    var scoreSyncService: ScoreInfoSyncServicing { get }
    var gameScheduleSyncService: GameScheduleSyncServicing { get }
    var gameHistorySyncService: GameHistorySyncServicing { get }
    var timelineSyncService: GameTimelineService { get }
    var personDataStore: DetermineStatePersonDataStore { get }
    var commonStateStore: DetermineStateSyncStore { get }
    var gameStartReminder: any GameStartReminderServicing { get }

    var gameDashboardTelemetry: GameDashboardTelemetryServicing? { get }
    var usernameStorage: UsernameStoring { get }
    var airdropService: AirdropServicing { get }

    func setup()
    func throttle()

    func setupGameRegistrationService() throws -> GameRegisterServicing

    func createTattooTerminationService(candidate: ProofOfInkPallet.Candidate) throws -> TattooTerminateServicing

    func getDepositAsset() throws -> ChainAsset
}

class DIM2SharedFlowState {
    let candidateWallet: WalletManaging
    let score: WalletManaging
    let vrfManager: BandersnatchKeyManaging
    let chatEncryptionManager: MessageExchangeEncryptionMaking
    let chainRegistry: ChainRegistryProtocol
    let chainId: ChainModel.Id
    let personDataStore: DetermineStatePersonDataStore
    let commonStateStore: DetermineStateSyncStore
    let gameSyncService: GameInfoSyncServicing
    let scoreSyncService: ScoreInfoSyncServicing
    let gameScheduleSyncService: GameScheduleSyncServicing
    let gameHistorySyncService: GameHistorySyncServicing
    let timelineSyncService: GameTimelineService
    let substrateStorageFacade: StorageFacadeProtocol
    let operationQueue: OperationQueue
    let logger: LoggerProtocol
    let gameStartReminder: any GameStartReminderServicing
    let gameDashboardTelemetry: GameDashboardTelemetryServicing?
    let usernameStorage: UsernameStoring
    let airdropService: AirdropServicing

    init(
        candidateWallet: WalletManaging,
        score: WalletManaging,
        vrfManager: BandersnatchKeyManaging,
        chatEncryptionManager: MessageExchangeEncryptionMaking,
        chainRegistry: ChainRegistryProtocol,
        chainId: ChainModel.Id,
        personDataStore: DetermineStatePersonDataStore,
        commonStateStore: DetermineStateSyncStore,
        gameInfoSyncService: GameInfoSyncServicing,
        scoreInfoSyncService: ScoreInfoSyncServicing,
        substrateStorageFacade: StorageFacadeProtocol,
        operationQueue: OperationQueue,
        gameStartReminder: any GameStartReminderServicing,
        logger: LoggerProtocol,
        usernameStorage: UsernameStoring = UsernameStorage()
    ) throws {
        self.candidateWallet = candidateWallet
        self.score = score
        self.vrfManager = vrfManager
        self.chatEncryptionManager = chatEncryptionManager
        self.chainRegistry = chainRegistry
        self.chainId = chainId
        self.personDataStore = personDataStore
        self.commonStateStore = commonStateStore
        gameSyncService = gameInfoSyncService
        scoreSyncService = scoreInfoSyncService
        self.substrateStorageFacade = substrateStorageFacade
        self.operationQueue = operationQueue
        self.gameStartReminder = gameStartReminder
        self.logger = logger
        self.usernameStorage = usernameStorage

        let connection = try chainRegistry.getConnectionOrError(for: chainId)
        let runtimeService = try chainRegistry.getRuntimeProviderOrError(for: chainId)

        #if TESTNET_FEATURE
            let chainForTelemetry = try? chainRegistry.getChainOrError(for: chainId)
            gameDashboardTelemetry = chainForTelemetry.map { chain in
                let client = GameDashboardTelemetryClient(baseURL: AppConfig.gameDashboardBaseURL)
                return GameDashboardTelemetryEmitter(
                    client: client,
                    chainFormat: chain.chainFormat
                )
            }
        #else
            gameDashboardTelemetry = nil
        #endif

        gameScheduleSyncService = GameScheduleSyncService(
            connection: connection,
            runtimeService: runtimeService
        )

        gameHistorySyncService = GameHistorySyncService(
            accountOrPerson: nil,
            connection: connection,
            runtimeService: runtimeService
        )

        timelineSyncService = GameTimelineService(
            infoSyncService: gameSyncService,
            synchronizedTimeService: SynchronizedTimeService()
        )

        airdropService = AirdropService(
            chainRegistry: chainRegistry,
            candidateWallet: candidateWallet,
            vrfManager: vrfManager,
            personDataStore: personDataStore,
            logger: logger
        )
    }
}

extension DIM2SharedFlowState: DIM2SharedFlowStateProtocol {
    var source: People.RegisteredSource? {
        personDataStore.currentState?.makeRegisteredData()?.source
    }

    func setup() {
        gameSyncService.setup()
        scoreSyncService.setup()
        gameScheduleSyncService.setup()
        gameHistorySyncService.setup()
        timelineSyncService.setup()

        personDataStore.add(
            observer: self,
            queue: nil
        ) { [weak self] _, newPersonData in
            guard let accountOrPerson = newPersonData?.makeAccountOrPerson() else {
                return
            }

            self?.gameHistorySyncService.setAccountOrPerson(accountOrPerson)
        }
    }

    func throttle() {
        personDataStore.remove(observer: self)

        gameSyncService.throttle()
        scoreSyncService.throttle()
        gameScheduleSyncService.throttle()
        gameHistorySyncService.throttle()
        timelineSyncService.throttle()
    }

    func setupGameRegistrationService() throws -> GameRegisterServicing {
        let chain = try chainRegistry.getChainOrError(for: chainId)

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: substrateStorageFacade,
            operationQueue: operationQueue
        )

        let extrinsicSubmissionMonitor = try extrinsicSubmissionFacade.createMonitorFactory(chain: chain)

        let encryptionIdentifier = try Chat.OnChainEncryptionIdentifier.x25519(
            Chat.PublicKey(rawData: chatEncryptionManager.localPublicKey)
        )

        return GameRegisterService(
            chain: chain,
            candidateWallet: candidateWallet,
            scoreWallet: score,
            encryptionIdentifier: encryptionIdentifier,
            extrinsicSubmitMonitor: extrinsicSubmissionMonitor,
            candidateOriginFactory: CandidateOriginFactory(
                chainRegistry: chainRegistry,
                operationQueue: operationQueue,
                logger: logger
            ),
            personhoodOriginFactory: PersonhoodOriginFactory(
                vrfManager: vrfManager,
                chainRegistry: chainRegistry,
                operationQueue: operationQueue,
                logger: logger
            )
        )
    }

    func createTattooTerminationService(
        candidate: ProofOfInkPallet.Candidate
    ) throws -> TattooTerminateServicing {
        let chain = try chainRegistry.getChainOrError(for: chainId)

        let extrinsicSubmissionFacade = ExtrinsicSubmissionMonitorFacade(
            chainRegistry: chainRegistry,
            substrateStorageFacade: substrateStorageFacade,
            operationQueue: operationQueue
        )

        let extrinsicSubmissionMonitor = try extrinsicSubmissionFacade.createMonitorFactory(chain: chain)

        return TattooTerminationService(
            extrinsicOriginFactory: ExtrinsicOriginFactory.personCandidate(),
            extrinsicMonitoring: extrinsicSubmissionMonitor,
            candidate: candidate,
            wallet: candidateWallet,
            chain: chain
        )
    }

    func getDepositAsset() throws -> ChainAsset {
        let chain = try chainRegistry.getChainOrError(for: chainId)

        return try chain.chainAssetOrError(for: AppConfig.Assets.dimAsset.assetId)
    }
}
