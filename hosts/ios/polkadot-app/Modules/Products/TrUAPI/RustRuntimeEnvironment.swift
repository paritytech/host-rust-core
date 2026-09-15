import Foundation
import TrUAPIHost
import Products
import ChainRegistry
import SubstrateSdk
import BulletinChain

/// Shared dependencies for opening one product execution off the process-wide
/// ``TrUAPIHostRuntime``. Embedded by both the SPA and chat rust runtime
/// factories. Session activation lives on the shared runtime, so no session
/// data is held here.
struct RustRuntimeEnvironment {
    let runtime: TrUAPIHostRuntime
    let chainRegistry: ChainRegistryProtocol
    let notificationScheduler: ProductNotificationScheduling
    let ipfsFetcher: IpfsFetching
    let hostProvider: ProductHostProviding
    let logger: LoggerProtocol

    /// The rust pieces a runtime needs: the opened execution and its chain
    /// connection pool for lifecycle control.
    struct ExecutionModel {
        let execution: TrUAPIProductExecutionProtocol
        let chainConnections: TrUAPIChainConnecting

        /// Start the localhost ws-bridge and return the bootstrap script to
        /// inject. Called from the runtime's `start`; opening the execution
        /// (``makeSPAExecution``/``makeChatExecution``) stays side-effect free.
        /// The local session is activated once on the shared runtime, not here.
        func startBridge() async throws -> String {
            let webRtcAllowed = try await execution.permissionAuthorizationStatus(
                request: .remote(RemotePermissionRequest(permission: .webRtc))
            ) == .authorized
            let endpoint = try execution.startWsBridge(bindPort: 0)
            return LocalhostBridgeBootstrap.script(
                port: endpoint.port,
                token: endpoint.token,
                webRtcAllowed: webRtcAllowed
            )
        }
    }

    /// Open an SPA execution for `productId`. No ws-bridge start; that happens
    /// in the runtime's `start` via ``ExecutionModel/startBridge()``. The
    /// execution retains the bridge (callback retainer) and the bridge retains
    /// the pool, so holding `ExecutionModel` pins the whole chain.
    func makeSPAExecution(productId: ProductId, routers: ProductRoutersFacadeProtocol) throws -> ExecutionModel {
        try makeExecution(productId: productId, routers: routers, kind: .app)
    }

    /// Open a chat execution for `productId`. Mirrors ``makeSPAExecution``.
    /// TODO(chat PR): open with ``RustChatExecutionBridge`` and pass it as
    /// `chat:` to wire the native chat surface once the integration lands.
    func makeChatExecution(productId: ProductId, routers: ProductRoutersFacadeProtocol) throws -> ExecutionModel {
        try makeExecution(productId: productId, routers: routers, kind: .worker)
    }
}

private extension RustRuntimeEnvironment {
    func makeExecution(
        productId: ProductId,
        routers: ProductRoutersFacadeProtocol,
        kind: ProductExecutionKind
    ) throws -> ExecutionModel {
        let chainConnections = TrUAPIChainConnectionPool(
            engineResolver: { [chainRegistry] genesisHash in
                chainRegistry.getChainByGenesis(for: genesisHash.toHex()).flatMap { chain in
                    chainRegistry.getConnection(for: chain.chainId)
                }
            },
            logger: logger
        )

        let bridge = RustProductExecutionBridge(dependencies: makeBridgeDependencies(
            productId: productId,
            routers: routers,
            chainConnections: chainConnections
        ))

        let execution = try runtime.openProductExecution(
            bridge: bridge,
            configuration: ProductExecutionConfig(productId: productId, executionKind: kind),
            chat: nil
        )

        bridge.attach(execution)

        return ExecutionModel(execution: execution, chainConnections: chainConnections)
    }

    func makeBridgeDependencies(
        productId: ProductId,
        routers: ProductRoutersFacadeProtocol,
        chainConnections: TrUAPIChainConnecting
    ) -> RustProductExecutionBridge.Dependencies {
        RustProductExecutionBridge.Dependencies(
            productId: productId,
            permissionGuard: ProductPermissionGuard.create(router: routers.productsRouter),
            notificationScheduler: notificationScheduler,
            navigationRouter: routers.navigationRouter,
            chainRegistry: chainRegistry,
            chainConnections: chainConnections,
            productStorage: TrUAPILocalStorage.createProductLocalStorage(productId: productId),
            coreStorage: TrUAPILocalStorage.createCoreLocalStorage(),
            confirmationPresenter: TrUAPIConfirmationPresenter(routerFacade: routers),
            preimageCache: TrUAPIPreimageCache { [logger, ipfsFetcher] key in
                do {
                    return try await ipfsFetcher.lookupBy(rawHash: key)
                } catch {
                    logger.error("[truapi] preimage fetch failed for \(key.toHex()): \(error)")
                    return nil
                }
            },
            hostProvider: hostProvider,
            logger: logger
        )
    }
}
