import Foundation
import Operation_iOS
import KeyDerivation
import ChainRegistry

class PersonRegistrationStateFetcher {
    private let mobRuleWallet: WalletManaging
    private let scoreWallet: WalletManaging
    private let resourcesWallet: WalletManaging
    private let vrfManager: BandersnatchKeyManaging

    private let chain: ChainModel
    private let runtimeProvider: RuntimeProviderProtocol
    private let connectionFactory: ConnectionFactoryProtocol
    private let queryFactory: PersonRegistrationQueryFactoryProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    private let fetchCancellable = CancellableCallStore()

    init(
        mobRuleWallet: WalletManaging,
        scoreWallet: WalletManaging,
        resourcesWallet: WalletManaging,
        vrfManager: BandersnatchKeyManaging,
        chain: ChainModel,
        runtimeProvider: RuntimeProviderProtocol,
        connectionFactory: ConnectionFactoryProtocol,
        queryFactory: PersonRegistrationQueryFactoryProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.mobRuleWallet = mobRuleWallet
        self.scoreWallet = scoreWallet
        self.resourcesWallet = resourcesWallet
        self.vrfManager = vrfManager
        self.chain = chain
        self.runtimeProvider = runtimeProvider
        self.connectionFactory = connectionFactory
        self.queryFactory = queryFactory
        self.operationQueue = operationQueue
        self.logger = logger
    }

    deinit {
        fetchCancellable.cancel()
    }
}

// MARK: - Internal

extension PersonRegistrationStateFetcher {
    func fetchSyncState(completion: @escaping (PersonRegistrationSyncState?) -> Void) {
        guard
            let mobRuleAccountId = try? mobRuleWallet.fetchAccount(for: chain).accountId,
            let scoreAccountId = try? scoreWallet.fetchAccount(for: chain).accountId,
            let resourcesAccountId = try? resourcesWallet.fetchAccount(for: chain).accountId,
            let memberKey = try? vrfManager.getMemberKey()
        else {
            logger.warning("No account for \(chain.name)")
            completion(nil)
            return
        }

        let connection: ChainConnection

        do {
            connection = try connectionFactory.createConnection(
                for: chain,
                delegate: nil
            )
        } catch {
            logger.error("Failed to create connection with error: \(error.localizedDescription)")
            completion(nil)
            return
        }

        fetchCancellable.cancel()

        let wrapper = queryFactory.querySyncState(
            input: .init(
                mobRuleAccountId: mobRuleAccountId,
                scoreAccountId: scoreAccountId,
                resourcesAccountId: resourcesAccountId,
                memberKey: memberKey
            ),
            connection: connection,
            runtimeProvider: runtimeProvider
        )

        executeCancellable(
            wrapper: wrapper,
            inOperationQueue: operationQueue,
            backingCallIn: fetchCancellable,
            runningCallbackIn: .main
        ) { result in
            connection.disconnect(true)

            switch result {
            case let .success(state):
                completion(state)
            case .failure:
                completion(nil)
            }
        }
    }

    func cancelFetch() {
        fetchCancellable.cancel()
    }
}
