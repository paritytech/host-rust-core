import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import Individuality

typealias IndexToPlayerKeysByRound = [GamePallet.RoundIndex: [GamePallet.IndexToPlayerKey]]
typealias PlayersByRound = [GamePallet.RoundIndex: [AccountId]]
typealias PlayersByAlias = [Data: AccountId]

protocol GameInfoOperationMaking {
    func fetchPlayersByRound(
        for indexToPlayerKeys: IndexToPlayerKeysByRound,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        blockHash: Data?
    ) -> CompoundOperationWrapper<PlayersByRound>

    func fetchPlayersByAlias(
        for aliasesClosure: @escaping () throws -> [Data],
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        blockHash: Data?
    ) -> CompoundOperationWrapper<PlayersByAlias>
}

final class GameInfoOperationFactory {
    private let operationQueue: OperationQueue
    private let logger: LoggerProtocol
    private let storageRequestFactory: StorageRequestFactory

    init(
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.operationQueue = operationQueue
        self.logger = logger

        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}

extension GameInfoOperationFactory: GameInfoOperationMaking {
    func fetchPlayersByRound(
        for indexToPlayerKeys: IndexToPlayerKeysByRound,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        blockHash: Data?
    ) -> CompoundOperationWrapper<PlayersByRound> {
        let codingFactoryOperation = runtimeService.fetchCoderFactoryOperation()

        let keys = indexToPlayerKeys
            .values
            .flatMap { $0 }

        let fetchPlayersWrapper: CompoundOperationWrapper<
            [StorageResponse<GamePallet.AccountOrPerson>]
        > = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { keys },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: GamePallet.indexToPlayer,
            at: blockHash
        )
        fetchPlayersWrapper.addDependency(operations: [codingFactoryOperation])

        let aliasesToFetchOperation = aliasesToFetchOperation(
            fetchPlayersDependency: fetchPlayersWrapper
        )

        let fetchPlayersByAliasWrapper = fetchPlayersByAlias(
            for: { try aliasesToFetchOperation.extractNoCancellableResultData() },
            connection: connection,
            runtimeService: runtimeService,
            blockHash: blockHash
        )
        fetchPlayersByAliasWrapper.addDependency(operations: [aliasesToFetchOperation])

        let resultOperation = playersByRoundResultOperation(
            keys: keys,
            fetchPlayersDependency: fetchPlayersWrapper,
            fetchPlayersByAliasDependency: fetchPlayersByAliasWrapper
        )

        return .init(
            targetOperation: resultOperation,
            dependencies: [codingFactoryOperation, aliasesToFetchOperation]
                + fetchPlayersWrapper.allOperations
                + fetchPlayersByAliasWrapper.allOperations
        )
    }

    func fetchPlayersByAlias(
        for aliasesClosure: @escaping () throws -> [Data],
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        blockHash: Data?
    ) -> CompoundOperationWrapper<PlayersByAlias> {
        let codingFactoryOperation = runtimeService.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<[StorageResponse<BytesCodable>]>
        fetchWrapper = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { try aliasesClosure().map { BytesCodable(wrappedValue: $0) } },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: GamePallet.aliasToAccount,
            at: blockHash
        )
        fetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<PlayersByAlias> {
            let aliases = try aliasesClosure()

            guard !aliases.isEmpty else {
                return [:]
            }

            let responses = try fetchWrapper.targetOperation.extractNoCancellableResultData()

            return zip(aliases, responses).reduce(into: PlayersByAlias()) { result, pair in
                if let accountId = pair.1.value?.wrappedValue {
                    result[pair.0] = accountId
                }
            }
        }
        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingHead(operations: [codingFactoryOperation])
            .insertingTail(operation: mappingOperation)
    }
}

private extension GameInfoOperationFactory {
    func aliasesToFetchOperation(
        fetchPlayersDependency: CompoundOperationWrapper<
            [StorageResponse<GamePallet.AccountOrPerson>]
        >
    ) -> BaseOperation<[Data]> {
        let operation = ClosureOperation<[Data]> {
            let responses = try fetchPlayersDependency.targetOperation.extractNoCancellableResultData()
            var set = Set<Data>()
            responses.forEach { response in
                switch response.value {
                case let .person(alias):
                    set.insert(alias)
                case .account,
                     nil:
                    break
                }
            }
            return Array(set)
        }
        operation.addDependency(fetchPlayersDependency.targetOperation)
        return operation
    }

    func playersByRoundResultOperation(
        keys: [GamePallet.IndexToPlayerKey],
        fetchPlayersDependency: CompoundOperationWrapper<
            [StorageResponse<GamePallet.AccountOrPerson>]
        >,
        fetchPlayersByAliasDependency: CompoundOperationWrapper<PlayersByAlias>
    ) -> BaseOperation<PlayersByRound> {
        let operation = ClosureOperation<PlayersByRound> { [logger] in
            let responses = try fetchPlayersDependency.targetOperation.extractNoCancellableResultData()
            let playersByAlias = try fetchPlayersByAliasDependency.targetOperation.extractNoCancellableResultData()
            var result = PlayersByRound()

            responses.enumerated().forEach { index, response in
                let key = keys[index]

                var player: AccountId?

                switch response.value {
                case let .account(accountId):
                    player = accountId
                case let .person(alias):
                    if let accountId = playersByAlias[alias] {
                        player = accountId
                    } else {
                        logger.error("Missing alias to player for key \(key)")
                    }
                case nil:
                    logger.error("Missing player response for key \(key)")
                }

                guard let player else {
                    return
                }

                var players = result[key.roundIndex] ?? []
                players.append(player)
                result[key.roundIndex] = players
            }

            return result
        }
        operation.addDependency(fetchPlayersByAliasDependency.targetOperation)
        return operation
    }
}
