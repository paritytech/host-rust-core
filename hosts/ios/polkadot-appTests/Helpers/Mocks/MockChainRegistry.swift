import Foundation
import Operation_iOS
import SubstrateSdk
import ChainRegistry

@testable import polkadot_app

/// `ChainRegistryProtocol` is `Sendable`, and the registry is read from the background tasks the
/// subjects spawn while a test configures it from the test thread, so every access to the stubbed
/// state goes through `mutex`.
final class MockChainRegistry: ChainRegistryProtocol, @unchecked Sendable {
    private let mutex = NSLock()

    private var storedChainsByGenesis: [String: ChainModel] = [:]
    private var storedRuntimeProviders: [String: RuntimeProviderProtocol] = [:]
    private var storedConnectionsByChainId: [ChainModel.Id: ChainConnection] = [:]

    var chainsByGenesis: [String: ChainModel] {
        get { mutex.withLock { storedChainsByGenesis } }
        set { mutex.withLock { storedChainsByGenesis = newValue } }
    }

    var runtimeProviders: [String: RuntimeProviderProtocol] {
        get { mutex.withLock { storedRuntimeProviders } }
        set { mutex.withLock { storedRuntimeProviders = newValue } }
    }

    var connectionsByChainId: [ChainModel.Id: ChainConnection] {
        get { mutex.withLock { storedConnectionsByChainId } }
        set { mutex.withLock { storedConnectionsByChainId = newValue } }
    }

    var availableChainIds: Set<ChainModel.Id>? { nil }
    var allAvailableChains: [ChainModel] { Array(chainsByGenesis.values) }

    func getChain(for _: ChainModel.Id) -> ChainModel? { nil }
    func getChainByGenesis(for genesisHash: ChainModel.Id) -> ChainModel? { chainsByGenesis[genesisHash] }
    func getConnection(for chainId: ChainModel.Id) -> ChainConnection? { connectionsByChainId[chainId] }
    func getOneShotConnection(for _: ChainModel.Id) -> JSONRPCEngine? { nil }
    func retainConnections(_: ConnectionRetainScope) -> ConnectionRetainToken { ConnectionRetainToken() }
    func getRuntimeProvider(for chainId: ChainModel.Id) -> RuntimeProviderProtocol? { runtimeProviders[chainId] }
    func switchSync(mode _: ChainSyncMode, chainId _: ChainModel.Id) throws {}
    func chainsSubscribe(
        _: AnyObject,
        runningInQueue _: DispatchQueue,
        updateClosure _: @escaping ([DataProviderChange<ChainModel>]) -> Void
    ) {}
    func chainsUnsubscribe(_: AnyObject) {}
    func subscribeChainState(_: ConnectionStateSubscription, chainId _: ChainModel.Id) {}
    func unsubscribeChainState(_: ConnectionStateSubscription, chainId _: ChainModel.Id) {}
    func syncUp() {}
}
