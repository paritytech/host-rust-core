import Foundation

public struct DotNsConfig {
    public let contractsChainId: String
    /// Serves names with no registry entry.
    public let resolverContractAddress: Data
    /// Maps a node to its own resolver. Nil disables manifest resolution.
    public let nameRegistryContractAddress: Data?
    public let ipfsGatewayBaseUrl: URL

    public init(
        contractsChainId: String,
        resolverContractAddress: Data,
        nameRegistryContractAddress: Data?,
        ipfsGatewayBaseUrl: URL
    ) {
        self.contractsChainId = contractsChainId
        self.resolverContractAddress = resolverContractAddress
        self.nameRegistryContractAddress = nameRegistryContractAddress
        self.ipfsGatewayBaseUrl = ipfsGatewayBaseUrl
    }
}
