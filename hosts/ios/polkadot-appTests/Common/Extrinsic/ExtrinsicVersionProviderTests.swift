import Foundation
import Testing
import SubstrateSdk
import ChainRegistry
@testable import polkadot_app

@Suite("ExtrinsicVersionProvider")
struct ExtrinsicVersionProviderTests {
    private func makeProvider(versions: [ChainModel.Id: UInt8] = [:]) -> ExtrinsicVersionProvider {
        let config = MockRemoteConfigManager()
        config.txExtensionVersions = versions
        return ExtrinsicVersionProvider(
            extensionVersionProvider: ExtrinsicExtensionVersionProvider(remoteConfig: config)
        )
    }

    private func isV4(_ version: Extrinsic.Version) -> Bool {
        if case .V4 = version { true } else { false }
    }

    private func isV5(_ version: Extrinsic.Version, extensionVersion: UInt8) -> Bool {
        if case let .V5(value) = version { value == extensionVersion } else { false }
    }

    @Test("Username chain uses V5 with the per-chain remote-config extension version")
    func usernameChainUsesRemoteConfigVersion() {
        let chain = AppConfig.Chains.usernameChain
        let provider = makeProvider(versions: [chain: 3])

        #expect(isV5(provider.getExtrinsicVersion(for: chain, isSigned: true), extensionVersion: 3))
        #expect(isV5(provider.getExtrinsicVersion(for: chain, isSigned: false), extensionVersion: 3))
    }

    @Test("Username chain defaults to extension version 0 when absent from remote config")
    func usernameChainDefaultsToZero() {
        let chain = AppConfig.Chains.usernameChain

        #expect(isV5(makeProvider().getExtrinsicVersion(for: chain, isSigned: true), extensionVersion: 0))
    }

    @Test("AssetHub is V4 when signed and V5 (remote-config version) when unsigned")
    func assetHubDependsOnIsSigned() {
        let chain = AppConfig.Chains.assethubChain
        let provider = makeProvider(versions: [chain: 2])

        #expect(isV4(provider.getExtrinsicVersion(for: chain, isSigned: true)))
        #expect(isV5(provider.getExtrinsicVersion(for: chain, isSigned: false), extensionVersion: 2))
    }

    @Test("Unknown chains fall back to V4 regardless of remote config")
    func unknownChainFallsBackToV4() {
        let unknown: ChainModel.Id = "0x00000000000000000000000000000000000000000000000000000000deadbeef"
        let provider = makeProvider(versions: [unknown: 5])

        #expect(isV4(provider.getExtrinsicVersion(for: unknown, isSigned: true)))
        #expect(isV4(provider.getExtrinsicVersion(for: unknown, isSigned: false)))
    }
}
