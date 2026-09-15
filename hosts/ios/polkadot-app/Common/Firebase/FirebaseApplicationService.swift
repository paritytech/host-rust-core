import Foundation
import Operation_iOS
import FirebaseCore
import FirebaseRemoteConfig
import Combine
import ChainRegistry

protocol RemoteConfigDelegate: AnyObject {
    func remoteConfig(didFinishLoading result: Result<Void, Error>)
    func remoteConfig(appVersionDidChange result: Result<String, Error>)
}

extension RemoteConfigDelegate {
    func remoteConfig(didFinishLoading _: Result<Void, Error>) {}
    func remoteConfig(appVersionDidChange _: Result<String, Error>) {}
}

final class FirebaseApplicationService: RemoteConfigManaging {
    static let shared = FirebaseApplicationService()

    // MARK: Properties

    private let remoteConfig: FirebaseRemoteConfig.RemoteConfig

    weak var delegate: (any RemoteConfigDelegate)?
    private let logger: LoggerProtocol = Logger.shared

    // MARK: Initial methods

    private init() {
        #if DEBUG
            var args = ProcessInfo.processInfo.arguments
            args.append("-FIRDebugEnabled")
            ProcessInfo.processInfo.setValue(args, forKey: "arguments")
            FirebaseConfiguration.shared.setLoggerLevel(.info)
        #else
            var args = ProcessInfo.processInfo.arguments
            args.append("-FIRDebugDisabled")
            ProcessInfo.processInfo.setValue(args, forKey: "arguments")
        #endif

        FirebaseApp.configure()
        remoteConfig = FirebaseRemoteConfig.RemoteConfig.remoteConfig()

        configurationRemoteConfigSettings()
    }

    // MARK: Public methods

    func fetchRemoteConfigValues() {
        Task {
            do {
                let signal: CustomSignal = .environment
                try await remoteConfig.setCustomSignals([signal.key: signal.value])
                let status = try await remoteConfig.fetchAndActivate()
                handleRemoteConfigStatus(status)
            } catch {
                delegate?.remoteConfig(didFinishLoading: .failure(error))
            }
        }
    }

    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]> {
        asyncWaitForRemoteConfigValues(for: .chains)
    }

    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .xcmTransfers)
    }

    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .generalXcmConfig)
    }

    func asyncWaitGameResultsFallbackURL() -> CompoundOperationWrapper<URL> {
        asyncWaitForRemoteConfigValues(for: .gameResultsFallbackURL)
    }

    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T> {
        asyncWaitForRemoteConfigValues(for: .w3sMerchants)
    }

    func asyncWaitCollectiblesFallbackURL() -> CompoundOperationWrapper<URL> {
        asyncWaitForRemoteConfigValues(for: .collectiblesFallbackURL)
    }

    func syncedCollectiblesEnabled() -> Bool {
        remoteConfig[.collectiblesEnabled].boolValue
    }

    func syncedTxExtensionVersions() -> [ChainModel.Id: UInt8] {
        guard let json = remoteConfig[.txExtensionVersions].jsonValue as? [String: Any] else {
            return [:]
        }

        return json.reduce(into: [:]) { result, entry in
            guard let number = entry.value as? NSNumber else { return }
            result[entry.key] = number.uint8Value
        }
    }

    func syncedAppConfig() -> RemoteAppConfig {
        RemoteAppConfig(
            identityBackendUrl: url(for: .identityBackendUrl),
            ipfsGatewayUrl: url(for: .ipfsGatewayUrl),
            gameDashboardUrl: url(for: .gameDashboardUrl),
            dotNsResolver: dotNsResolverAddress(),
            dotNsNameRegistry: dotNsNameRegistryAddress(),
            coinageInstanceId: coinageInstanceId(),
            fundingDomain: nonEmptyString(for: .fundingDomain)
        )
    }

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig {
        syncedAppConfig()
    }
}

private extension FirebaseApplicationService {
    // MARK: Private methods

    private func configurationRemoteConfigSettings() {
        let remoteConfigSettings = RemoteConfigSettings()
        remoteConfigSettings.minimumFetchInterval = .zero
        remoteConfig.configSettings = remoteConfigSettings
    }

    private func handleRemoteConfigStatus(_ status: RemoteConfigFetchAndActivateStatus) {
        defer {
            delegate?.remoteConfig(didFinishLoading: .success(()))
        }
        switch status {
        case .successFetchedFromRemote:
            logger.info("RemoteConfig fetched from remote and activated")
        case .successUsingPreFetchedData:
            logger.info("RemoteConfig activated using pre-fetched data")
        case .error:
            logger.error("Error during RemoteConfig activation")
        @unknown default:
            logger.error("Unknown status during RemoteConfig activation")
        }

        let appVersion = remoteConfig[.latestAppVersion].stringValue
        guard !appVersion.isEmpty else {
            logger.error("App version not found in RemoteConfig")
            delegate?.remoteConfig(appVersionDidChange: .failure(RemoteConfigError.versionNotFound))
            return
        }
        logger.info("Fetched latest app version: \(appVersion)")
        delegate?.remoteConfig(appVersionDidChange: .success(appVersion))
    }

    func nonEmptyString(for key: String) -> String? {
        let value = remoteConfig[key].stringValue
        return value.isEmpty ? nil : value
    }

    func url(for key: String) -> URL? {
        guard let value = nonEmptyString(for: key) else { return nil }
        return URL(string: value)
    }

    func dotNsConfigEntry(_ field: String, treatingEmptyAsMissing: Bool = false) -> String? {
        let json = remoteConfig[.dotNsResolver].jsonValue as? [String: String]
        guard let value = json?[field] else { return nil }

        return treatingEmptyAsMissing && value.isEmpty ? nil : value
    }

    func dotNsResolverAddress() -> String? {
        dotNsConfigEntry("resolverContractAddress")
    }

    func dotNsNameRegistryAddress() -> String? {
        // Empty counts as absent: payloads published before manifest support carry no name
        // registry, and an empty address would read as a configured one.
        dotNsConfigEntry("registryContractAddress", treatingEmptyAsMissing: true)
    }

    func coinageInstanceId() -> UInt32? {
        guard let value = nonEmptyString(for: .coinageInstanceId) else { return nil }
        return UInt32(value)
    }

    func asyncWaitForRemoteConfigValues<T: Decodable>(for key: String) -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper(targetOperation: AsyncClosureOperation<T>(
            operationClosure: { [logger, weak self] closure in
                guard let self else {
                    return
                }

                let data = remoteConfig[key].dataValue
                do {
                    let models = try JSONDecoder().decode(T.self, from: data)

                    closure(.success(models))
                } catch {
                    logger.error("Failed to decode remote config: \(error) \(key)")
                    closure(.failure(error))
                }
            },
            cancelationClosure: {}
        ))
    }
}

private extension FirebaseApplicationService {
    enum CustomSignal {
        case environment

        var key: String {
            switch self {
            case .environment:
                "environment"
            }
        }

        var value: FirebaseRemoteConfig.CustomSignalValue {
            switch self {
            case .environment:
                #if UNSTABLE
                    "unstable"
                #elseif NIGHTLY
                    "nightly"
                #else
                    "release"
                #endif
            }
        }
    }
}

// MARK: - Constants

private extension String {
    static let latestAppVersion = "latest_ios_version"
    static let chains = "chains_v2"
    static let xcmTransfers = "cross_chain_transfers"
    static let generalXcmConfig = "xcm_general_config"
    static let gameResultsFallbackURL = "game_results_fallback_url"
    static let w3sMerchants = "w3s_merchants"
    static let collectiblesFallbackURL = "collectibles_fallback_url"
    static let collectiblesEnabled = "collectibles_enabled"
    static let txExtensionVersions = "transaction_extension_versions"
    static let identityBackendUrl = "identity_backend_url"
    static let ipfsGatewayUrl = "ipfs_gateway_url"
    static let gameDashboardUrl = "game_dashboard_url"
    static let dotNsResolver = "dot_ns_config"
    static let coinageInstanceId = "coinage_instance_id"
    static let fundingDomain = "funding_domain"
}
