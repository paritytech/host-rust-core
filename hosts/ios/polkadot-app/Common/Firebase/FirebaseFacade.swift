import Foundation
import Operation_iOS
import SubstrateSdk
import Combine
import AsyncExtensions
import ChainRegistry
import FoundationExt

final class FirebaseFacade {
    private enum RemoteConfigOutcome {
        case valid(RemoteAppConfig)
        case invalid
    }

    static let shared = FirebaseFacade()

    private let firebaseService = FirebaseApplicationService.shared
    private let appConfigProvider: AppConfigProvider = .shared
    private let logger: LoggerProtocol?
    private var chainRegistry: ChainRegistryProtocol?

    private let remoteConfigSubject = AsyncCurrentValueSubject<RemoteConfigOutcome?>(nil)

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

    /// Waits for cached or fetched Remote Config before reading the reporting credentials.
    func asyncWaitIssueProxyConfiguration() async throws -> IssueProxyConfiguration {
        _ = try await asyncWaitRemoteConfig()
        return try firebaseService.syncedIssueProxyConfiguration()
    }
}

extension FirebaseFacade: RemoteConfigManaging, ChainRegistryConfiguring {
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
        for await outcome in remoteConfigSubject.compacted() {
            switch outcome {
            case let .valid(config):
                return config
            case .invalid:
                throw RemoteConfigError.invalidConfig
            }
        }

        throw CancellationError()
    }
}

extension FirebaseFacade: RemoteConfigObserving {
    func remoteConfigStream() -> AnyAsyncSequence<RemoteAppConfig> {
        // Invalid outcomes are dropped because they are never applied.
        remoteConfigSubject
            .compacted()
            .compactMap { outcome -> RemoteAppConfig? in
                guard case let .valid(config) = outcome else { return nil }
                return config
            }
            .eraseToAnyAsyncSequence()
    }
}

extension FirebaseFacade: RemoteConfigDelegate {
    func remoteConfig(didFinishLoading result: Result<Void, Error>) {
        switch result {
        case .success:
            let config = firebaseService.syncedAppConfig()
            if config.isValid {
                applyConfig(config)
            } else {
                remoteConfigSubject.send(.invalid)
            }
        case let .failure(failure):
            logger?.error(failure.localizedDescription)
            publishInvalidUnlessApplied()
        }
    }

    func remoteConfig(appVersionDidChange _: Result<String, Error>) {}
}

private extension FirebaseFacade {
    func applyCachedConfigIfValid() {
        let cached = firebaseService.syncedAppConfig()
        guard cached.isValid else {
            // A retry must wait for the new fetch instead of replaying the previous failure.
            if case .invalid = remoteConfigSubject.value {
                remoteConfigSubject.send(nil)
            }
            return
        }
        applyConfig(cached)
    }

    /// A failed fetch keeps an already applied config; without one, waiters would hang until their deadline.
    func publishInvalidUnlessApplied() {
        if case .valid = remoteConfigSubject.value { return }
        remoteConfigSubject.send(.invalid)
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
        remoteConfigSubject.send(.valid(config))
    }

    func waitUntilReachable() async throws {
        guard let reachabilityManager = ReachabilityManager.shared else { return }
        try await reachabilityManager.asyncWaitReachable()
    }
}
