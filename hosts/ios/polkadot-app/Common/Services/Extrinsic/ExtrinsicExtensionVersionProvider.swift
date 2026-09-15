import Foundation
import ChainStore
import SubstrateSdk

/// Extrinsic format selected by the caller. Unlike `Extrinsic.Version` this carries no extension
/// version payload — the extension version for V5 is resolved per-chain from remote config.
enum ConcreteExtrinsicVersion {
    // swiftlint:disable:next identifier_name
    case V4
    // swiftlint:disable:next identifier_name
    case V5
}

protocol ExtrinsicExtensionVersionProviding {
    /// Resolves the concrete `Extrinsic.Version` for the requested format. V4 carries no extension
    /// version; for V5 the extension version is sourced per-chain from remote config (default 0).
    func getExtensionVersion(for txVersion: ConcreteExtrinsicVersion, chainId: ChainId) -> Extrinsic.Version
}

final class ExtrinsicExtensionVersionProvider {
    private let remoteConfig: RemoteConfigManaging

    init(remoteConfig: RemoteConfigManaging = FirebaseApplicationService.shared) {
        self.remoteConfig = remoteConfig
    }
}

extension ExtrinsicExtensionVersionProvider: ExtrinsicExtensionVersionProviding {
    func getExtensionVersion(for txVersion: ConcreteExtrinsicVersion, chainId: ChainId) -> Extrinsic.Version {
        switch txVersion {
        case .V4:
            .V4
        case .V5:
            .V5(extensionVersion: remoteConfig.syncedTxExtensionVersions()[chainId] ?? 0)
        }
    }
}
