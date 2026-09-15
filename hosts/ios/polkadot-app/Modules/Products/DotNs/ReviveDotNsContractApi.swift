import Foundation
import os
import SubstrateSdk
import Products
import ChainRegistry

// Implementation of DotNsContractApiProtocol that calls the Revive pallet on Asset Hub.
final class ReviveDotNsContractApi: Sendable {
    private let chainRegistry: ChainRegistryProtocol
    private let configProvider: @Sendable () throws -> DotNsConfig
    private let caller: ReviveContractCalling

    // Every text or content read costs a name-registry lookup first, and one product resolution
    // reads four names. `.some(nil)` is a name the registry has no entry for, cached as
    // deliberately as a hit — legacy names have none and are read constantly.
    private let resolverCache = OSAllocatedUnfairLock(initialState: [String: Data?]())

    init(
        chainRegistry: ChainRegistryProtocol,
        configProvider: @Sendable @escaping () throws -> DotNsConfig,
        caller: ReviveContractCalling = ReviveContractCaller()
    ) {
        self.chainRegistry = chainRegistry
        self.configProvider = configProvider
        self.caller = caller
    }
}

private extension ReviveDotNsContractApi {
    func callReviveContract(contract: Data, inputData: Data) async throws -> Data {
        let config = try configProvider()

        guard let connection = chainRegistry.getConnection(for: config.contractsChainId) else {
            throw DotNsContractError.runtimeApiNotFound
        }

        guard let runtimeProvider = chainRegistry.getRuntimeProvider(for: config.contractsChainId) else {
            throw DotNsContractError.runtimeApiNotFound
        }

        let origin = AppConfig.reviveAccountId

        return try await caller.callReadOnly(
            connection: connection,
            runtimeProvider: runtimeProvider,
            caller: origin,
            contract: contract,
            input: inputData
        )
    }

    /// Where a name's content hash is read from. Legacy names have no registry entry of their own
    /// and keep resolving through the fixed address.
    func contentResolver(for node: Data, dotNsName: String) async throws -> Data {
        let config = try configProvider()

        return try await nameRegistryResolver(for: node, dotNsName: dotNsName)
            ?? config.resolverContractAddress
    }

    /// Content hash bytes for a name, retried through the fixed resolver when the resolver the
    /// registry named has no code at its address.
    func readContentHash(node: Data, dotNsName: String) async throws -> Data {
        let config = try configProvider()
        let resolver = try await contentResolver(for: node, dotNsName: dotNsName)

        let output = try await callReviveContract(
            contract: resolver,
            inputData: DotNsAbi.encodeContentHash(node: node)
        )

        guard output.isEmpty else { return output }

        guard resolver != config.resolverContractAddress else {
            throw DotNsContractError.contentHashNotFound
        }

        resolverCache.withLock { $0[dotNsName] = nil }

        let fallback = try await callReviveContract(
            contract: config.resolverContractAddress,
            inputData: DotNsAbi.encodeContentHash(node: node)
        )

        guard !fallback.isEmpty else {
            throw DotNsContractError.contentHashNotFound
        }

        return fallback
    }

    /// The resolver a name registered for itself, or nil when it has no registry entry. Callers
    /// that need content specifically want ``contentResolver(for:dotNsName:)`` and its fallback.
    func nameRegistryResolver(for node: Data, dotNsName: String) async throws -> Data? {
        let config = try configProvider()

        // An unconfigured name registry disables manifest resolution without breaking legacy names.
        guard let registry = config.nameRegistryContractAddress else {
            return nil
        }

        if let cached = resolverCache.withLock({ $0[dotNsName] }) {
            return cached
        }

        let output = try await callReviveContract(
            contract: registry,
            inputData: DotNsAbi.encodeResolver(node: node)
        )

        let resolver = output.isEmpty ? nil : DotNsAbi.decodeResolver(output: output)
        resolverCache.withLock { $0[dotNsName] = .some(resolver) }

        return resolver
    }
}

extension ReviveDotNsContractApi: DotNsContractApiProtocol {
    func resolveContentHash(dotNsName: String) async throws -> Data {
        let node = try NameHash.nameHash(dotNsName)
        let outputBytes = try await readContentHash(node: node, dotNsName: dotNsName)

        guard let contentHash = DotNsAbi.decodeContentHash(output: outputBytes) else {
            throw DotNsContractError.contentHashNotFound
        }

        return try Eip1577.stripPrefix(contentHash)
    }

    func getMetadata(dotNsName: String, key: String) async throws -> String? {
        let node = try NameHash.nameHash(dotNsName)

        // Text records live only on a name's own resolver, so a name without one has none.
        guard let resolver = try await nameRegistryResolver(for: node, dotNsName: dotNsName) else {
            return nil
        }

        let outputBytes = try await callReviveContract(
            contract: resolver,
            inputData: DotNsAbi.encodeText(node: node, key: key)
        )

        guard !outputBytes.isEmpty else {
            resolverCache.withLock { $0[dotNsName] = nil }
            return nil
        }

        return DotNsAbi.decodeText(output: outputBytes)
    }

    func clearCache() {
        resolverCache.withLock { $0.removeAll() }
    }
}
