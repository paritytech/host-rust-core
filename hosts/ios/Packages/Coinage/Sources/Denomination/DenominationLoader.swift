import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import BigInt

protocol DenominationContextLoaderProtocol {
    /// Fetches denomination context for the given asset.
    /// - Parameter asset: The asset providing decimal precision
    /// - Returns: A denomination breakdown context configured for the asset
    func fetchContext(for asset: AssetProtocol) async throws -> DenominationBreakdownContext
}

final class DenominationContextLoader: DenominationContextLoaderProtocol {
    private let instanceId: CoinageInstanceId
    private let connection: any JSONRPCEngine
    private let storageRequestFactory: any StorageRequestFactoryProtocol
    private let runtimeService: RuntimeCodingServiceProtocol

    init(
        instanceId: CoinageInstanceId,
        connection: any JSONRPCEngine,
        storageRequestFactory: any StorageRequestFactoryProtocol,
        runtimeService: RuntimeCodingServiceProtocol
    ) {
        self.instanceId = instanceId
        self.connection = connection
        self.storageRequestFactory = storageRequestFactory
        self.runtimeService = runtimeService
    }

    func fetchContext(for asset: AssetProtocol) async throws -> DenominationBreakdownContext {
        async let unit = fetchAssetUnit()

        async let maxExponent = runtimeService.fetchConstant(
            path: CoinagePallet.Constants.maximumExponent(),
            type: Int16.self
        )

        async let minExponent = runtimeService.fetchConstant(
            path: CoinagePallet.Constants.minimumExponent(),
            type: Int16.self
        )

        return try await DenominationBreakdownContext(
            unit: unit,
            precision: asset.decimalPrecision,
            maxExponent: maxExponent,
            minExponent: minExponent
        )
    }
}

private extension DenominationContextLoader {
    func fetchAssetUnit() async throws -> BigUInt {
        let coderFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        let record: CoinagePallet.InstanceRecord? = try await storageRequestFactory.queryItems(
            engine: connection,
            keyParams: { [instanceId] in [StringCodable(wrappedValue: instanceId)] },
            factory: { coderFactory },
            storagePath: CoinagePallet.Storage.instances(),
            at: nil
        )
        .asyncExecute()
        .first?
        .value

        guard let record else {
            throw CoinageError.notConfigured
        }

        return record.assetUnit
    }
}
