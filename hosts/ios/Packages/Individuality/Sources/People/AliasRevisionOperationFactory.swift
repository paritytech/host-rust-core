import Foundation
import KeyDerivation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery

public protocol AliasRevisionOperationMaking {
    func checkAliasRevision(
        accountIdClosure: @escaping () throws -> AccountId,
        blockHash: Data?
    ) -> CompoundOperationWrapper<AliasRevisionResult>
}

public final class AliasRevisionOperationFactory {
    private let connection: JSONRPCEngine
    private let runtimeProvider: RuntimeCodingServiceProtocol
    private let requestFactory: StorageRequestFactory
    private let collectionIdentifier: MembersPallet.CollectionIdentifier

    public init(
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol,
        collectionIdentifier: MembersPallet.CollectionIdentifier,
        operationQueue: OperationQueue
    ) {
        self.connection = connection
        self.runtimeProvider = runtimeProvider
        self.collectionIdentifier = collectionIdentifier
        requestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }
}

extension AliasRevisionOperationFactory: AliasRevisionOperationMaking {
    public func checkAliasRevision(
        accountIdClosure: @escaping () throws -> AccountId,
        blockHash: Data?
    ) -> CompoundOperationWrapper<AliasRevisionResult> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchAliasWrapper: CompoundOperationWrapper<
            [StorageResponse<PeoplePallet.RevisedContextualAlias>]
        > = requestFactory.queryItems(
            engine: connection,
            keyParams: { try [BytesCodable(wrappedValue: accountIdClosure())] },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PeoplePallet.accountToAliasPath,
            options: StorageQueryListOptions(atBlock: blockHash)
        )
        fetchAliasWrapper.addDependency(operations: [codingFactoryOperation])

        let fetchRingRootWrapper: CompoundOperationWrapper<
            [StorageResponse<MembersPallet.RingRoot>]
        > = requestFactory.queryItems(
            engine: connection,
            keyParams1: { [collectionIdentifier] in
                [BytesCodable(wrappedValue: collectionIdentifier)]
            },
            keyParams2: {
                guard let alias = try fetchAliasWrapper.targetOperation
                    .extractNoCancellableResultData().first?.value else {
                    throw AliasRevisionOperationError.requiredDataMissed
                }
                return [StringCodable(wrappedValue: alias.ring)]
            },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: MembersPallet.Storage.root(),
            options: StorageQueryListOptions(atBlock: blockHash)
        )

        fetchRingRootWrapper.addDependency(wrapper: fetchAliasWrapper)

        let resultOperation = ClosureOperation<AliasRevisionResult> {
            guard
                let alias = try fetchAliasWrapper.targetOperation
                .extractNoCancellableResultData().first?.value,
                let ringRoot = try fetchRingRootWrapper.targetOperation
                .extractNoCancellableResultData().first?.value
            else {
                throw AliasRevisionOperationError.requiredDataMissed
            }
            return .init(
                ring: alias.ring,
                isUpToDate: ringRoot.revision == alias.revision
            )
        }
        resultOperation.addDependency(fetchAliasWrapper.targetOperation)
        resultOperation.addDependency(fetchRingRootWrapper.targetOperation)

        return .init(
            targetOperation: resultOperation,
            dependencies: [codingFactoryOperation]
                + fetchAliasWrapper.allOperations
                + fetchRingRootWrapper.allOperations
        )
    }
}

extension AliasRevisionOperationFactory {
    enum AliasRevisionOperationError: Error {
        case requiredDataMissed
    }
}

public struct AliasRevisionResult {
    public let ring: MembersPallet.RingIndex
    public let isUpToDate: Bool
}
