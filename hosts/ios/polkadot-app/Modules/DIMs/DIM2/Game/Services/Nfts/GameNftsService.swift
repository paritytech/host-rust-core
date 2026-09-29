import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import Individuality

struct GameNft: Equatable {
    let hash: Data
    let mintedAt: UInt32
}

protocol GameNftsServicing {
    func fetchAllPlayerNfts(
        player: GamePallet.AccountOrPerson,
        blockHash: Data?
    ) async throws -> [GameNft]
}

final class GameNftsService: GameNftsServicing {
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let requestFactory = StorageRequestFactory.asyncInit()

    init(
        connection: JSONRPCEngine,
        runtimeService: RuntimeCodingServiceProtocol
    ) {
        self.connection = connection
        self.runtimeService = runtimeService
    }

    func fetchAllPlayerNfts(
        player: GamePallet.AccountOrPerson,
        blockHash: Data?
    ) async throws -> [GameNft] {
        Logger.shared
            .debug(
                "[GameDebug] nfts.fetchAllPlayerNfts start player=\(player.rawTypeValue) " +
                    "blockHash=\(blockHash?.toHex() ?? "head")"
            )

        let codingFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        let entries: [GamePallet.NftsKey: StringScaleMapper<UInt32>] = try await requestFactory.queryByPrefix(
            engine: connection,
            request: MapRemoteStorageRequest(storagePath: GamePallet.nfts) { player },
            storagePath: GamePallet.nfts,
            factory: { codingFactory },
            options: StorageQueryListOptions(atBlock: blockHash)
        )
        .asyncExecute()

        let allNfts = entries.map { GameNft(hash: $0.key.hash, mintedAt: $0.value.value) }
        Logger.shared
            .debug(
                "[GameDebug] nfts.fetchAllPlayerNfts returned count=\(allNfts.count) " +
                    "hashes=\(allNfts.map { $0.hash.toHex() })"
            )
        return allNfts
    }
}
