import Foundation
import Operation_iOS
import SubstrateSdk
import SubstrateStorageQuery
import ChainRegistry

protocol PrivacyVoucherOperationMaking {
    func fetchKeysToRing(
        forVoucherKeys voucherKeys: [Data],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.KeysToRing?]>

    func fetchUsedTickets(
        for keysToRing: [PrivacyVoucherPallet.KeysToRing],
        aliases: [Data],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.UsedTicket?]>

    func fetchClaimableRings(
        for keysToRing: [PrivacyVoucherPallet.KeysToRing],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.ClaimableRing?]>

    func fetchBuildingRings(
        for balancesOf: [Balance],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.BuildingRing?]>

    func fetchKeys(
        for keysToRing: PrivacyVoucherPallet.KeysToRing,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.MemberKey]>
}

final class PrivacyVoucherOperationFactory: PrivacyVoucherOperationMaking {
    private let operationQueue: OperationQueue
    private let storageRequestFactory: StorageRequestFactory

    init(
        operationQueue: OperationQueue = OperationManagerFacade.sharedDefaultQueue
    ) {
        self.operationQueue = operationQueue

        storageRequestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )
    }

    func fetchKeysToRing(
        forVoucherKeys voucherKeys: [Data],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.KeysToRing?]> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrappers: CompoundOperationWrapper<[StorageResponse<PrivacyVoucherPallet.KeysToRing>]>
        fetchWrappers = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: {
                voucherKeys.map { BytesCodable(wrappedValue: $0) }
            },
            factory: {
                try codingFactoryOperation.extractNoCancellableResultData()
            },
            storagePath: PrivacyVoucherPallet.keysToRing
        )

        fetchWrappers.addDependency(operations: [codingFactoryOperation])

        let mapOperation = ClosureOperation<[PrivacyVoucherPallet.KeysToRing?]> {
            let results = try fetchWrappers.targetOperation.extractNoCancellableResultData()

            return results.map(\.value)
        }

        mapOperation.addDependency(fetchWrappers.targetOperation)

        return fetchWrappers
            .insertingHead(operations: [codingFactoryOperation])
            .insertingTail(operation: mapOperation)
    }

    func fetchUsedTickets(
        for keysToRing: [PrivacyVoucherPallet.KeysToRing],
        aliases: [Data],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.UsedTicket?]> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<[StorageResponse<PrivacyVoucherPallet.UsedTicket>]>

        fetchWrapper = storageRequestFactory.queryNMapItems(
            engine: connection,
            nParamKeys: {
                aliases.indices.map { index in
                    PrivacyVoucherPallet.UsedTicketKey(
                        balanceOf: keysToRing[index].balanceOf,
                        ringIndex: keysToRing[index].ringIndex,
                        alias: aliases[index]
                    )
                }
            },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PrivacyVoucherPallet.usedTickets
        )

        fetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<[PrivacyVoucherPallet.UsedTicket?]> {
            let responses = try fetchWrapper.targetOperation.extractNoCancellableResultData()
            return responses.map(\.value)
        }

        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingTail(operation: mappingOperation)
            .insertingHead(operations: [codingFactoryOperation])
    }

    func fetchClaimableRings(
        for keysToRing: [PrivacyVoucherPallet.KeysToRing],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.ClaimableRing?]> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<[StorageResponse<PrivacyVoucherPallet.ClaimableRing>]>

        let differentKeys = Array(Set(keysToRing))

        fetchWrapper = storageRequestFactory.queryItems(
            engine: connection,
            keyParams1: { differentKeys.map { StringCodable(wrappedValue: $0.balanceOf) } },
            keyParams2: { differentKeys.map { StringCodable(wrappedValue: $0.ringIndex) } },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PrivacyVoucherPallet.rings
        )

        fetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<[PrivacyVoucherPallet.ClaimableRing?]> {
            let responses = try fetchWrapper.targetOperation.extractNoCancellableResultData()

            let dict: [PrivacyVoucherPallet.KeysToRing: PrivacyVoucherPallet.ClaimableRing] = zip(
                differentKeys,
                responses
            ).reduce(into: [:]) {
                $0[$1.0] = $1.1.value
            }

            return keysToRing.map { dict[$0] }
        }

        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingTail(operation: mappingOperation)
            .insertingHead(operations: [codingFactoryOperation])
    }

    func fetchBuildingRings(
        for balancesOf: [Balance],
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.BuildingRing?]> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<[StorageResponse<PrivacyVoucherPallet.BuildingRing>]>

        let differentKeys = Array(Set(balancesOf))

        fetchWrapper = storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { differentKeys.map { StringCodable(wrappedValue: $0) } },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PrivacyVoucherPallet.buildingRings
        )

        fetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<[PrivacyVoucherPallet.BuildingRing?]> {
            let responses = try fetchWrapper.targetOperation.extractNoCancellableResultData()

            let dict: [Balance: PrivacyVoucherPallet.BuildingRing] = zip(
                differentKeys,
                responses
            ).reduce(into: [:]) {
                $0[$1.0] = $1.1.value
            }

            return balancesOf.map { dict[$0] }
        }

        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingTail(operation: mappingOperation)
            .insertingHead(operations: [codingFactoryOperation])
    }

    func fetchKeys(
        for keysToRing: PrivacyVoucherPallet.KeysToRing,
        connection: JSONRPCEngine,
        runtimeProvider: RuntimeProviderProtocol
    ) -> CompoundOperationWrapper<[PrivacyVoucherPallet.MemberKey]> {
        let codingFactoryOperation = runtimeProvider.fetchCoderFactoryOperation()

        let fetchWrapper: CompoundOperationWrapper<[StorageResponse<[BytesCodable]>]>

        let requestFactory = StorageRequestFactory(
            remoteFactory: StorageKeyFactory(),
            operationManager: OperationManager(operationQueue: operationQueue)
        )

        fetchWrapper = requestFactory.queryItems(
            engine: connection,
            keyParams1: { [StringCodable(wrappedValue: keysToRing.balanceOf)] },
            keyParams2: { [StringCodable(wrappedValue: keysToRing.ringIndex)] },
            factory: { try codingFactoryOperation.extractNoCancellableResultData() },
            storagePath: PrivacyVoucherPallet.keysPath
        )

        fetchWrapper.addDependency(operations: [codingFactoryOperation])

        let mappingOperation = ClosureOperation<[PrivacyVoucherPallet.MemberKey]> {
            try fetchWrapper.targetOperation.extractNoCancellableResultData()
                .flatMap { $0.value ?? [] }
                .map(\.wrappedValue)
        }

        mappingOperation.addDependency(fetchWrapper.targetOperation)

        return fetchWrapper
            .insertingTail(operation: mappingOperation)
            .insertingHead(operations: [codingFactoryOperation])
    }
}
