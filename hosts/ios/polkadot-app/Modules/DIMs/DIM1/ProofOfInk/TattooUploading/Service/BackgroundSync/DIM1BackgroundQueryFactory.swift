import Foundation
import SubstrateSdk
import Operation_iOS
import SubstrateStorageQuery
import Individuality
import ChainRegistry

protocol DIM1BackgroundQueryFactoryProtocol {
    func querySyncState(
        input: DIM1BackgroundSyncInput,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<DIM1BackgroundSyncState>
}

struct DIM1BackgroundSyncInput {
    let candidateAccountId: AccountId
}

final class DIM1BackgroundQueryFactory {
    private let storageRequestFactory: StorageRequestFactoryProtocol
    private let stateFactory: DIM1BackgroundStateFactoryProtocol
    private let operationQueue: OperationQueue

    init(operationQueue: OperationQueue) {
        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
        stateFactory = DIM1BackgroundStateFactory()
        self.operationQueue = operationQueue
    }
}

extension DIM1BackgroundQueryFactory: DIM1BackgroundQueryFactoryProtocol {
    func querySyncState(
        input: DIM1BackgroundSyncInput,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<DIM1BackgroundSyncState> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let candidateWrapper: CompoundOperationWrapper<[StorageResponse<ProofOfInkPallet.Candidate>]>
        candidateWrapper = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [BytesCodable(wrappedValue: input.candidateAccountId)] },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: ProofOfInkPallet.candidatesPath
        )

        candidateWrapper.addDependency(operations: [codingFactoryOperation])

        let finalMappingOperation = ClosureOperation<DIM1BackgroundSyncState> { [stateFactory] in
            let candidateResponses = try candidateWrapper.targetOperation.extractNoCancellableResultData()
            return stateFactory.makeState(candidate: candidateResponses.first?.value)
        }

        finalMappingOperation.addDependency(candidateWrapper.targetOperation)

        return CompoundOperationWrapper(
            targetOperation: finalMappingOperation,
            dependencies: [codingFactoryOperation] + candidateWrapper.allOperations
        )
    }
}
