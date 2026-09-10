import Foundation
import Operation_iOS
import CommonService
import KeyDerivation
import ChainRegistry

final class TattooUploadingServiceCoordinator {
    let candidateWallet: WalletManaging
    let mobRuleWallet: WalletManaging
    let scoreWallet: WalletManaging
    let resourcesWallet: WalletManaging
    let stateSyncObservers: [PersonhoodRegistrationSyncObserver]
    let chainRegistry: ChainRegistryProtocol
    let processingQueue: DispatchQueue
    let operationQueue: OperationQueue
    let vrfRepo: BandersnatchManagerRepositoryProtocol
    let logger: LoggerProtocol

    let evidenceSubmissionStore: EvidenceSubmissionStateStore

    private var peopleSyncService: ApplicationServiceProtocol?
    private var bulletInSyncService: ApplicationServiceProtocol?

    private var isActive: Bool = false

    init(
        candidateWallet: WalletManaging,
        mobRuleWallet: WalletManaging,
        scoreWallet: WalletManaging,
        resourcesWallet: WalletManaging,
        stateSyncObservers: [PersonhoodRegistrationSyncObserver],
        chainRegistry: ChainRegistryProtocol,
        operationQueue: OperationQueue,
        processingQueue: DispatchQueue,
        vrfRepo: BandersnatchManagerRepositoryProtocol = .shared,
        logger: LoggerProtocol
    ) {
        self.candidateWallet = candidateWallet
        self.mobRuleWallet = mobRuleWallet
        self.scoreWallet = scoreWallet
        self.resourcesWallet = resourcesWallet
        self.stateSyncObservers = stateSyncObservers
        self.chainRegistry = chainRegistry
        self.operationQueue = operationQueue
        self.processingQueue = processingQueue
        self.vrfRepo = vrfRepo

        evidenceSubmissionStore = EvidenceSubmissionStateStore(logger: logger)

        self.logger = logger
    }

    private func setupPeopleSyncServiceIfNeeded(for chain: ChainModel) {
        guard peopleSyncService == nil else {
            return
        }

        guard
            let connection = chainRegistry.getConnection(for: chain.chainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chain.chainId)
        else {
            logger.warning("No connection or runtime for \(chain.name)")
            return
        }

        guard
            let candidateAccountId = try? candidateWallet.fetchAccount(for: chain).accountId,
            let mobRuleAccountId = try? mobRuleWallet.fetchAccount(for: chain).accountId,
            let scoreAccountId = try? scoreWallet.fetchAccount(for: chain).accountId,
            let resourcesAccountId = try? resourcesWallet.fetchAccount(for: chain).accountId,
            let memberKey = try? vrfRepo.fullPerson().getMemberKey()
        else {
            logger.warning("No account for \(chain.name)")
            return
        }

        logger.debug("Setuping people service for \(chain.name)")
        logger.debug("candidateAccountId: \(candidateAccountId.base64EncodedString())")
        logger.debug("mobRuleAccountId: \(mobRuleAccountId.base64EncodedString())")
        logger.debug("scoreAccountId: \(scoreAccountId.base64EncodedString())")
        logger.debug("memberKey: \(memberKey.base64EncodedString())")

        peopleSyncService = PersonhoodRegistrationSyncService(
            candidateAccountId: candidateAccountId,
            mobRuleAccountId: mobRuleAccountId,
            scoreAccountId: scoreAccountId,
            resourcesAccountId: resourcesAccountId,
            memberKey: memberKey,
            connection: connection,
            runtimeService: runtimeProvider,
            observers: [evidenceSubmissionStore] + stateSyncObservers,
            operationQueue: operationQueue,
            proccessingQueue: processingQueue,
            logger: logger
        )

        peopleSyncService?.setup()
    }

    private func throttlePeopleServiceIfNeeded() {
        peopleSyncService?.throttle()
        peopleSyncService = nil
    }

    private func setupBulletInSyncServiceIfNeeded(for chain: ChainModel) {
        guard bulletInSyncService == nil else {
            return
        }

        guard let accountId = try? candidateWallet.fetchAccount(for: chain).accountId else {
            logger.warning("No account for \(chain.name)")
            return
        }

        guard
            let connection = chainRegistry.getConnection(for: chain.chainId),
            let runtimeProvider = chainRegistry.getRuntimeProvider(for: chain.chainId) else {
            logger.warning("No connection or runtime for \(chain.name)")
            return
        }

        logger.debug("Setuping transaction storage service for \(chain.name)")

        bulletInSyncService = TattooUploadingBulletInSyncService(
            accountId: accountId,
            connection: connection,
            runtimeService: runtimeProvider,
            observers: [evidenceSubmissionStore],
            operationQueue: operationQueue,
            processingQueue: processingQueue,
            logger: logger
        )

        bulletInSyncService?.setup()
    }

    private func throttleBulletInServiceIfNeeded() {
        bulletInSyncService?.throttle()
        bulletInSyncService = nil
    }

    private func handleNew(chain: ChainModel) {
        if chain.chainId == AppConfig.Chains.usernameChain {
            setupPeopleSyncServiceIfNeeded(for: chain)
        }

        if chain.chainId == AppConfig.Chains.bulletInChain {
            setupBulletInSyncServiceIfNeeded(for: chain)
        }
    }

    private func handleRemove(chainId: ChainModel.Id) {
        if chainId == AppConfig.Chains.usernameChain {
            throttlePeopleServiceIfNeeded()
        }

        if chainId == AppConfig.Chains.bulletInChain {
            throttleBulletInServiceIfNeeded()
        }
    }

    private func subscribeChains() {
        chainRegistry.chainsSubscribe(
            self,
            runningInQueue: processingQueue
        ) { [weak self] changes in
            for change in changes {
                switch change {
                case let .insert(chain),
                     let .update(chain):
                    self?.handleNew(chain: chain)
                case let .delete(deletedIdentifier):
                    self?.handleRemove(chainId: deletedIdentifier)
                }
            }
        }
    }
}

extension TattooUploadingServiceCoordinator: ApplicationServiceProtocol {
    func setup() {
        guard !isActive else {
            return
        }

        isActive = true

        subscribeChains()
    }

    func throttle() {
        guard isActive else {
            return
        }

        isActive = false

        chainRegistry.chainsUnsubscribe(self)
        throttleBulletInServiceIfNeeded()
        throttlePeopleServiceIfNeeded()

        evidenceSubmissionStore.reset()
    }
}
