import Foundation
import Operation_iOS
import ChainRegistry

@testable import polkadot_app

final class MockRemoteConfigManager: RemoteConfigManaging {
    var chainsToReturn: [RemoteChainModel] = []
    var errorToThrow: Error?
    var collectiblesEnabled = false
    var txExtensionVersions: [ChainModel.Id: UInt8] = [:]
    var remoteConfig = RemoteAppConfig(
        identityBackendUrl: URL(string: "https://polkadot-app-stg.parity.io/"),
        ipfsGatewayUrl: nil,
        gameDashboardUrl: nil,
        dotNsResolver: nil,
        dotNsNameRegistry: nil,
        coinageInstanceId: nil,
        fundingDomain: nil
    )

    func fetchRemoteConfigValues() {}

    func asyncWaitRemoteConfig() async throws -> RemoteAppConfig {
        if let error = errorToThrow {
            throw error
        }
        return remoteConfig
    }

    func syncedCollectiblesEnabled() -> Bool {
        collectiblesEnabled
    }

    func syncedTxExtensionVersions() -> [ChainModel.Id: UInt8] {
        txExtensionVersions
    }

    func asyncWaitChainsForRemoteConfigValues() -> CompoundOperationWrapper<[RemoteChainModel]> {
        if let error = errorToThrow {
            return CompoundOperationWrapper.createWithError(error)
        }
        return CompoundOperationWrapper.createWithResult(chainsToReturn)
    }

    func asyncWaitXcmTransfers<T: Decodable>() -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper.createWithError(NSError(domain: "mock", code: 0))
    }

    func asyncWaitXcmGeneralConfig<T: Decodable>() -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper.createWithError(NSError(domain: "mock", code: 0))
    }

    func asyncWaitW3sMerchants<T: Decodable>() -> CompoundOperationWrapper<T> {
        CompoundOperationWrapper.createWithError(NSError(domain: "mock", code: 0))
    }
}
