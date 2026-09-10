import Foundation
import Operation_iOS
import KeyDerivation
import ChainRegistry

class DIM1BackgroundStateFetcher {
    private let candidateWallet: WalletManaging

    private let chain: ChainModel
    private let runtimeProvider: RuntimeProviderProtocol
    private let connectionFactory: ConnectionFactoryProtocol
    private let queryFactory: DIM1BackgroundQueryFactoryProtocol
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol

    private let fetchCancellable = CancellableCallStore()

    init(
        candidateWallet: WalletManaging,
        chain: ChainModel,
        runtimeProvider: RuntimeProviderProtocol,
        connectionFactory: ConnectionFactoryProtocol,
        queryFactory: DIM1BackgroundQueryFactoryProtocol,
        operationQueue: OperationQueue,
        logger: LoggerProtocol
    ) {
        self.candidateWallet = candidateWallet
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

extension DIM1BackgroundStateFetcher {
    func fetchSyncState(completion: @escaping (DIM1BackgroundSyncState?) -> Void) {
        guard let candidateAccountId = try? candidateWallet.fetchAccount(for: chain).accountId else {
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
            input: .init(candidateAccountId: candidateAccountId),
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
