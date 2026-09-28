import Foundation
import UIKit
import UIKitExt
import TrUAPIHost
import ChainRegistry
import Products
import SubstrateSdk
import KeyDerivation
import Keystore_iOS

/// Runtime configuration error raised while assembling the shared host config.
enum TrUAPIRuntimeConfigError: Error {
    case missingGenesisHash(chain: String)
}

/// Vends the process-wide ``TrUAPIHostRuntime``. Product executions open off
/// the single shared runtime, so its authentication and core services are
/// shared across every SPA and chat product.
protocol TrUAPIHostRuntimeProviding: AnyObject, Sendable {
    /// Return the shared runtime, building and activating its local session on
    /// first use. Concurrent first calls share one build, later calls return
    /// the built instance, and a failed build is forgotten so the next call
    /// retries.
    func sharedRuntime() async throws -> TrUAPIHostRuntime

    /// Anchor the host's core confirmations (signing, permission prompts) to
    /// the given view. Until it is attached, host-level prompts deny.
    @MainActor func setPresentationView(_ view: ControllerBackedProtocol)
}

/// Builds one ``TrUAPIHostRuntime`` from host identity + people/bulletin
/// genesis hashes + the local session secret, which activates the local
/// session, and caches it. The build runs off the caller's thread, is started
/// at launch and retried on demand, so it can wait until chains are synced
/// and a session secret exists.
actor TrUAPIHostRuntimeProvider: TrUAPIHostRuntimeProviding {
    private let chainRegistry: ChainRegistryProtocol
    private let entropyManager: RootEntropyManaging
    private let settingsManager: SettingsManagerProtocol
    private let coreStorage: TrUAPILocalStoring
    private let confirmationRouterFacade: ProductRoutersFacadeProtocol
    private let tldProvider: DotNsTldProviding
    private let logger: LoggerProtocol

    private var buildTask: Task<TrUAPIHostRuntime, Error>?

    init(
        chainRegistry: ChainRegistryProtocol,
        entropyManager: RootEntropyManaging,
        settingsManager: SettingsManagerProtocol,
        coreStorage: TrUAPILocalStoring,
        confirmationRouterFacade: ProductRoutersFacadeProtocol,
        tldProvider: DotNsTldProviding = DotNsTldProviderFacade.shared,
        logger: LoggerProtocol
    ) {
        self.chainRegistry = chainRegistry
        self.entropyManager = entropyManager
        self.settingsManager = settingsManager
        self.coreStorage = coreStorage
        self.confirmationRouterFacade = confirmationRouterFacade
        self.tldProvider = tldProvider
        self.logger = logger
    }

    @MainActor
    func setPresentationView(_ view: ControllerBackedProtocol) {
        confirmationRouterFacade.setPresentationView(view)
    }

    func sharedRuntime() async throws -> TrUAPIHostRuntime {
        let task = buildTask ?? Task { try await buildRuntime() }
        buildTask = task
        do {
            return try await task.value
        } catch {
            if buildTask == task {
                buildTask = nil
            }
            throw error
        }
    }
}

private extension TrUAPIHostRuntimeProvider {
    func buildRuntime() async throws -> TrUAPIHostRuntime {
        let secret = try entropyManager.fetchRootEntropy()
        let networkSuffix = try tldProvider.currentTldOrError()
        let runtimeConfig = try await Self.makeRuntimeConfig(
            chainRegistry: chainRegistry,
            platformVersion: UIDevice.current.systemVersion,
            secret: secret,
            liteUsername: settingsManager.string(for: .username),
            networkSuffix: networkSuffix
        )

        let chainConnections = TrUAPIChainConnectionPool(
            engineResolver: { [chainRegistry] genesisHash in
                chainRegistry.getChainByGenesis(for: genesisHash.toHex()).flatMap { chain in
                    chainRegistry.getConnection(for: chain.chainId)
                }
            },
            logger: logger
        )

        let bridge = RustHostRuntimeBridge(
            chainRegistry: chainRegistry,
            coreStorage: coreStorage,
            chainConnections: chainConnections,
            confirmationPresenter: TrUAPIConfirmationPresenter(routerFacade: confirmationRouterFacade),
            logger: logger
        )

        let runtime = try await TrUAPIHostRuntime(bridge: bridge, runtimeConfig: runtimeConfig)
        bridge.attach(runtime)
        return runtime
    }
}

extension TrUAPIHostRuntimeProvider {
    /// Assemble the immutable host-wide config. Genesis hashes are fetched from
    /// the registry and must resolve; a missing hash fails explicitly rather
    /// than degrading. `networkSuffix` is the dotNS TLD the core derives the
    /// wallet's reserved identities under, so it has to be the one the app's own
    /// built-in accounts derive from. Exposed for testing the genesis-validation
    /// seam.
    static func makeRuntimeConfig(
        chainRegistry: ChainRegistryProtocol,
        platformVersion: String,
        secret: Data,
        liteUsername: String?,
        networkSuffix: String
    ) throws -> HostRuntimeConfig {
        let peopleChain = try chainRegistry.getChainOrError(for: AppConfig.Chains.usernameChain)
        let bulletinChain = try chainRegistry.getChainOrError(for: AppConfig.Chains.bulletInChain)
        let assetHubChain = try chainRegistry.getChainOrError(for: AppConfig.Chains.assethubChain)

        guard let peopleGenesisHex = peopleChain.explicitGenesisHash else {
            throw TrUAPIRuntimeConfigError.missingGenesisHash(chain: "people")
        }
        guard let bulletinGenesisHex = bulletinChain.explicitGenesisHash else {
            throw TrUAPIRuntimeConfigError.missingGenesisHash(chain: "bulletin")
        }
        // Product manifests are read from the dotNS contracts on Asset Hub, so
        // a missing hash here refuses every cross-product `trustedProducts`
        // grant indistinguishably from the other product granting nothing.
        // Fail explicitly, like its siblings, rather than passing all-zero.
        guard let assetHubGenesisHex = assetHubChain.explicitGenesisHash else {
            throw TrUAPIRuntimeConfigError.missingGenesisHash(chain: "assetHub")
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

        return try HostRuntimeConfig(
            hostName: "Polkadot App",
            hostVersion: version,
            platformType: "ios",
            platformVersion: platformVersion,
            peopleChainGenesisHash: Data(hexString: peopleGenesisHex),
            bulletinChainGenesisHash: Data(hexString: bulletinGenesisHex),
            assetHubChainGenesisHash: Data(hexString: assetHubGenesisHex),
            networkSuffix: networkSuffix,
            localSessionSecret: secret,
            localSessionLiteUsername: liteUsername
        )
    }
}
