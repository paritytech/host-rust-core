import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import Individuality
import ChainRegistry

protocol CollectiblesCollectionServicing {
    func loadOwnedNfts() async -> [CollectionInput.OwnedNft]
}

final class CollectiblesCollectionService {
    private let chainRegistry: ChainRegistryProtocol
    private let personDataStore: DetermineStatePersonDataStore
    private let requestFactory: StorageRequestFactoryProtocol
    private let logger: LoggerProtocol

    init(
        personDataStore: DetermineStatePersonDataStore,
        chainRegistry: ChainRegistryProtocol = ChainRegistryFacade.sharedRegistry,
        requestFactory: StorageRequestFactoryProtocol = StorageRequestFactory.asyncInit(),
        logger: LoggerProtocol = Logger.shared
    ) {
        self.personDataStore = personDataStore
        self.chainRegistry = chainRegistry
        self.requestFactory = requestFactory
        self.logger = logger
    }
}

extension CollectiblesCollectionService: CollectiblesCollectionServicing {
    func loadOwnedNfts() async -> [CollectionInput.OwnedNft] {
        do {
            return try await fetchOwned()
        } catch {
            logger.error("[Collectibles] failed to load collection: \(error)")
            return []
        }
    }
}

private extension CollectiblesCollectionService {
    func fetchOwned() async throws -> [CollectionInput.OwnedNft] {
        guard let chain = chainRegistry.getChain(for: AppConfig.Chains.usernameChain) else {
            throw CollectiblesError.missingChain
        }

        guard let account = GameAccountFactory.makeAccount(chain: chain, registeredSource: .game) else {
            throw CollectiblesError.missingAccount
        }

        let connection = try chainRegistry.getConnectionOrError(for: chain.chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chain.chainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()

        let owner = personDataStore.currentState?.makeAccountOrPerson()
            ?? .account(accountID: account.accountId)

        async let confirmed: [GamePallet.NftKey: StringScaleMapper<UInt32>] = requestFactory.queryByPrefix(
            engine: connection,
            request: MapRemoteStorageRequest(storagePath: GamePallet.nfts) { owner },
            storagePath: GamePallet.nfts,
            factory: { codingFactory },
            options: StorageQueryListOptions(atBlock: nil)
        )
        .asyncExecute()

        async let pending: [GamePallet.NftKey: IgnoredValue] = requestFactory.queryByPrefix(
            engine: connection,
            request: MapRemoteStorageRequest(storagePath: GamePallet.nftCandidates) { owner },
            storagePath: GamePallet.nftCandidates,
            factory: { codingFactory },
            options: StorageQueryListOptions(atBlock: nil)
        )
        .asyncExecute()

        let confirmedMap = try await confirmed
        let pendingMap = try await pending

        return makeOwnedNfts(confirmed: confirmedMap, pendingKeys: Array(pendingMap.keys))
    }

    func makeOwnedNfts(
        confirmed: [GamePallet.NftKey: StringScaleMapper<UInt32>],
        pendingKeys: [GamePallet.NftKey]
    ) -> [CollectionInput.OwnedNft] {
        let confirmedItems = confirmed.map { key, mintedAt in
            CollectionInput.OwnedNft(
                hash: key.hash.toHex(),
                mintedAt: Int(mintedAt.value),
                pending: nil
            )
        }

        let confirmedHashes = Set(confirmed.keys.map(\.hash))
        let pendingItems = pendingKeys
            .filter { !confirmedHashes.contains($0.hash) }
            .map { key in
                CollectionInput.OwnedNft(
                    hash: key.hash.toHex(),
                    mintedAt: nil,
                    pending: true
                )
            }

        return confirmedItems + pendingItems
    }

    struct IgnoredValue: Decodable {
        init(from _: Decoder) throws {}
    }
}

private enum CollectiblesError: Error {
    case missingChain
    case missingAccount
}
