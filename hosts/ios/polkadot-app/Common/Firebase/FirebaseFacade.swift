import Foundation
import Operation_iOS
import SubstrateSdk
import Combine
import AsyncExtensions
import ChainRegistry
import FoundationExt

final class FirebaseFacade {
    static let shared = FirebaseFacade()

    private let firebaseService = FirebaseApplicationService.shared
    private let appConfigProvider: AppConfigProvider = .shared
    private let logger: LoggerProtocol?
    private var chainRegistry: ChainRegistryProtocol?

    private let remoteConfigSubject = AsyncCurrentValueSubject<RemoteAppConfig?>(nil)

    private let appStateStreamFactory = ApplicationStateStreamFactory()
    private let foregroundRefreshInterval: TimeInterval = .secondsInHour
    private var lastRemoteFetchAt: Date?
    private var foregroundTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?

    private init(logger: LoggerProtocol? = Logger.shared) {
        self.logger = logger
        firebaseService.delegate = self

        startForegroundRefresh()
    }

    func set(chainRegistry registry: ChainRegistryProtocol) {
        chainRegistry = registry
    }
}

extension FirebaseFacade: RemoteConfigManaging {
    func fetchRemoteConfigValues() {
        applyCachedConfigIfValid()
        scheduleRemoteFetch()
    }

    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]> {
        firebaseService.asyncWaitChainsForRemoteConfigValues()
    }

    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T> {
        firebaseService.asyncWaitXcmTransfers()
    }

    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T> {
        firebaseService.asyncWaitXcmGeneralConfig()
    }

    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T> {
        firebaseService.asyncWaitW3sMerchants()
    }

    func syncedCollectiblesEnabled() -> Bool {
        firebaseService.syncedCollectiblesEnabled()
    }

    func syncedTxExtensionVersions() -> [ChainModel.Id: UInt8] {
        firebaseService.syncedTxExtensionVersions()
    }

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig {
        for await config in remoteConfigSubject.compacted() {
            return config
        }

        throw CancellationError()
    }
}

extension FirebaseFacade: RemoteConfigDelegate {
    func remoteConfig(didFinishLoading result: Result<Void, Error>) {
        switch result {
        case .success:
            applyConfig(firebaseService.syncedAppConfig())
        case let .failure(failure):
            logger?.error(failure.localizedDescription)
        }
    }

    func remoteConfig(appVersionDidChange _: Result<String, Error>) {}
}

private extension FirebaseFacade {
    func applyCachedConfigIfValid() {
        let cached = firebaseService.syncedAppConfig()
        guard cached.isValid else { return }
        applyConfig(cached)
    }

    func scheduleRemoteFetch() {
        guard fetchTask == nil else { return }

        lastRemoteFetchAt = Date()

        fetchTask = Task { @MainActor [unowned self] in
            try? await waitUntilReachable()
            firebaseService.fetchRemoteConfigValues()
            fetchTask = nil
        }
    }

    func startForegroundRefresh() {
        let foregroundEvents = appStateStreamFactory.stream(for: .willEnterForeground)

        foregroundTask = Task { @MainActor [weak self] in
            for await _ in foregroundEvents {
                self?.refreshRemoteConfigOnForeground()
            }
        }
    }

    func refreshRemoteConfigOnForeground() {
        guard shouldRefreshOnForeground else { return }
        scheduleRemoteFetch()
    }

    var shouldRefreshOnForeground: Bool {
        guard let lastRemoteFetchAt else { return true }
        return Date().timeIntervalSince(lastRemoteFetchAt) >= foregroundRefreshInterval
    }

    func applyConfig(_ config: RemoteAppConfig) {
        appConfigProvider.apply(config)
        chainRegistry?.syncUp()
        remoteConfigSubject.send(config)
    }

    func waitUntilReachable() async throws {
        guard let reachabilityManager = ReachabilityManager.shared else { return }
        try await reachabilityManager.asyncWaitReachable()
    }
}
