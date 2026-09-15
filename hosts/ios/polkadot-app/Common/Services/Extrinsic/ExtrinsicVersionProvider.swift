import Foundation
import ChainStore
import SubstrateSdk

protocol ExtrinsicVersionProviding {
    func getExtrinsicVersion(for chainId: ChainId, isSigned: Bool) -> Extrinsic.Version
}

final class ExtrinsicVersionProvider {
    private let extensionVersionProvider: ExtrinsicExtensionVersionProviding

    init(extensionVersionProvider: ExtrinsicExtensionVersionProviding = ExtrinsicExtensionVersionProvider()) {
        self.extensionVersionProvider = extensionVersionProvider
    }
}

extension ExtrinsicVersionProvider: ExtrinsicVersionProviding {
    func getExtrinsicVersion(for chainId: ChainId, isSigned: Bool) -> Extrinsic.Version {
        // The chain decides the format (V4 vs V5); isSigned is retained so AssetHub signed stays V4.
        let usesV5: Bool =
            switch chainId {
            case AppConfig.Chains.usernameChain: true
            case AppConfig.Chains.assethubChain: !isSigned
            default: false
            }

        guard usesV5 else { return .V4 }

        return extensionVersionProvider.getExtensionVersion(for: .V5, chainId: chainId)
    }
}
