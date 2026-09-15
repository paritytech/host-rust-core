import Foundation
import Individuality
import Products
import ChainRegistry
@preconcurrency import SubstrateStorageQuery
import StructuredConcurrency

/// Reads the TLD label from the `NetworkSuffix` pallet on the contracts chain, where the runtime
/// keeps the same suffix that personhood proof contexts are built from.
final class NetworkSuffixTldReader: Sendable {
    private let chainRegistry: ChainRegistryProtocol
    private let storageRequestFactory: StorageRequestFactoryProtocol
    private let configProvider: @Sendable () throws -> DotNsConfig

    init(
        chainRegistry: ChainRegistryProtocol,
        storageRequestFactory: StorageRequestFactoryProtocol,
        configProvider: @Sendable @escaping () throws -> DotNsConfig
    ) {
        self.chainRegistry = chainRegistry
        self.storageRequestFactory = storageRequestFactory
        self.configProvider = configProvider
    }
}

extension NetworkSuffixTldReader: DotNsTldReading {
    func readTld() async throws -> String {
        let config = try configProvider()
        let connection = try chainRegistry.getRpcConnectionOrError(for: config.contractsChainId)
        let runtimeProvider = try chainRegistry.getRuntimeCodingServiceOrError(for: config.contractsChainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        let suffix = try await storageRequestFactory.readNetworkSuffix(
            connection: connection,
            codingFactory: codingFactory
        )

        guard let decoded = String(data: suffix, encoding: .utf8) else {
            throw DotNsContractError.tldNotFound
        }

        let tld = String(decoded.trimmingPrefix("."))

        guard !tld.isEmpty, !tld.contains(".") else {
            throw DotNsContractError.tldNotFound
        }

        return tld
    }
}
