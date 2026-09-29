import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import Individuality
import ChainStore

protocol ProofOfInkOperationFactoryProtocol {
    func fetchFamily(
        at index: ProofOfInkPallet.FamilyIndex,
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol
    ) -> CompoundOperationWrapper<ProofOfInkPallet.Family?>
    func fetchAllFamilies(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol
    ) -> CompoundOperationWrapper<ProofOfInkPallet.DesignFamiliesResult>

    func fetchReservedDesignes(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol
    ) -> CompoundOperationWrapper<ProofOfInkPallet.ReservedDesignsResult>
}

extension ProofOfInkOperationFactoryProtocol {
    func fetchFamily(
        using index: ProofOfInkPallet.FamilyIndex,
        chainRegistry: ChainResourceProtocol,
        chainId: ChainId
    ) -> CompoundOperationWrapper<ProofOfInkPallet.Family?> {
        do {
            let connection = try chainRegistry.getRpcConnectionOrError(for: chainId)
            let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: chainId)
            return fetchFamily(
                at: index,
                for: connection,
                runtimeProvider: runtimeProvider
            )
        } catch {
            return .createWithError(error)
        }
    }
}

final class ProofOfInkOperationFactory {
    let operationQueue: OperationQueue

    init(operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue) {
        self.operationQueue = operationQueue
    }
}

extension ProofOfInkOperationFactory: ProofOfInkOperationFactoryProtocol {
    func fetchFamily(
        at index: ProofOfInkPallet.FamilyIndex,
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol
    ) -> CompoundOperationWrapper<ProofOfInkPallet.Family?> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchFamilyWrapper: CompoundOperationWrapper<[StorageResponse<ProofOfInkPallet.Family>]>

        let requestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
        fetchFamilyWrapper = requestFactory.queryItems(
            engine: connection,
            keyParams: {
                [StringScaleMapper(value: index)]
            },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: ProofOfInkPallet.designFamiliesPath
        )

        fetchFamilyWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<ProofOfInkPallet.Family?> {
            try fetchFamilyWrapper.targetOperation.extractNoCancellableResultData().first?.value
        }

        mappingOperation.addDependency(fetchFamilyWrapper.targetOperation)

        return fetchFamilyWrapper
            .insertingTail(operation: mappingOperation)
            .insertingHead(operations: [codingFactoryOperation])
    }

    func fetchAllFamilies(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol
    ) -> CompoundOperationWrapper<ProofOfInkPallet.DesignFamiliesResult> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<ProofOfInkPallet.DesignFamiliesResult>

        let requestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        fetchWrapper = requestFactory.queryByPrefix(
            engine: connection,
            request: UnkeyedRemoteStorageRequest(storagePath: ProofOfInkPallet.designFamiliesPath),
            storagePath: ProofOfInkPallet.designFamiliesPath,
            factory: {
                try codingFactoryOperation.extractNoCancellableResultData()
            }
        )

        fetchWrapper.addDependency(operations: [codingFactoryOperation])

        return fetchWrapper.insertingHead(operations: [codingFactoryOperation])
    }

    func fetchReservedDesignes(
        for connection: JSONRPCEngine,
        runtimeProvider: RuntimeCodingServiceProtocol
    ) -> CompoundOperationWrapper<ProofOfInkPallet.ReservedDesignsResult> {
        let keysQueryFactory = StorageKeysOperationFactory(operationQueue: operationQueue)

        let fetchWrapper: CompoundOperationWrapper<[ProofOfInkPallet.CommittedDesignKey]>

        fetchWrapper = keysQueryFactory.createKeysFetchWrapper(
            by: ProofOfInkPallet.committedDesignsPath,
            runtimeService: runtimeProvider,
            connection: connection
        )

        let mapOperation = ClosureOperation<ProofOfInkPallet.ReservedDesignsResult> {
            let items = try fetchWrapper.targetOperation.extractNoCancellableResultData()

            return items.reduce(into: ProofOfInkPallet.ReservedDesignsResult()) { accum, item in
                accum[item.familyIndex] = accum[item.familyIndex]?.union([item.designIndex])
                    ?? [item.designIndex]
            }
        }

        mapOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper.insertingTail(operation: mapOperation)
    }
}
