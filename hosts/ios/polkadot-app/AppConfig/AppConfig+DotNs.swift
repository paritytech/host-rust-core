import Foundation
import Products
import SubstrateSdk

extension AppConfig {
    static let reviveAccountId: AccountId = {
        let data = Data("modlpy/reviv".utf8)
        return data + Data(repeating: 0, count: 32 - data.count)
    }()
}

extension AppConfig {
    enum KnownIPFS {
        static var main: URL! {
            AppConfigProvider.shared.getRemoteConfig()!.ipfsGatewayUrl
        }
    }

    enum DotNs {
        private static var dotNsResolverAddress: String {
            AppConfigProvider.shared.getRemoteConfig()!.dotNsResolver!
        }

        /// Optional by design: an absent key disables manifest resolution and leaves legacy names
        /// working, so a value that will not decode has to degrade the same way rather than take
        /// every launch down with the rest of the config.
        private static var dotNsNameRegistryAddress: Data? {
            guard let raw = AppConfigProvider.shared.getRemoteConfig()?.dotNsNameRegistry else {
                return nil
            }

            return try? raw.fromHex()
        }

        static let dotNsBrowse = "browse"
        static var dotNsGetSome: String {
            AppConfigProvider.shared.getRemoteConfig()!.fundingDomain!
        }

        static let dotNsGameWebview = "game-webview"
        static let dotNsCollectibles = "collectibles-webview"

        static func config() throws -> DotNsConfig {
            let resolverAddress = try Self.dotNsResolverAddress.fromHex()

            return DotNsConfig(
                contractsChainId: AppConfig.Chains.assethubChain,
                resolverContractAddress: resolverAddress,
                nameRegistryContractAddress: Self.dotNsNameRegistryAddress,
                ipfsGatewayBaseUrl: AppConfig.KnownIPFS.main
            )
        }
    }
}
