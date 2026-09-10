import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import Individuality

typealias ActualGameDatesByIndex = [GamePallet.GameIndex: Date]

protocol GameHistoryOperationMaking {
    func fetchActualGameDates(
        with range: ClosedRange<GamePallet.GameIndex>,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        blockHash: Data?
    ) -> CompoundOperationWrapper<ActualGameDatesByIndex>
}

final class GameHistoryOperationFactory {
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

extension GameHistoryOperationFactory: GameHistoryOperationMaking {
    func fetchActualGameDates(
        with range: ClosedRange<GamePallet.GameIndex>,
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol,
        blockHash: Data?
    ) -> CompoundOperationWrapper<ActualGameDatesByIndex> {
        let indices = Array(range)

        let codingFactoryOperation = runtimeService.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<
            [StorageResponse<StringCodable<UInt32>>]
        > = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { indices.map { StringCodable(wrappedValue: $0) } },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: GamePallet.gameHistory,
            at: blockHash
        )
        fetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<ActualGameDatesByIndex> {
            let responses = try fetchWrapper.targetOperation.extractNoCancellableResultData()

            return zip(indices, responses).reduce(into: ActualGameDatesByIndex()) { result, pair in
                if let timestamp = pair.1.value?.wrappedValue, timestamp > 0 {
                    result[pair.0] = Date(timeIntervalSince1970: TimeInterval(timestamp))
                }
            }
        }
        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingHead(operations: [codingFactoryOperation])
            .insertingTail(operation: mappingOperation)
    }
}
