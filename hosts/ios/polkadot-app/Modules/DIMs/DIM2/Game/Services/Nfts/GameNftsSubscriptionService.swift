import Foundation
import SubstrateSdk
import SubstrateStorageSubscription
import SubstrateStorageQuery
import Operation_iOS
import StructuredConcurrency
import AsyncExtensions
import Individuality
import ChainRegistry

protocol GameNftsSubscriptionServicing: AnyObject {
    func observeMints(
        player: GamePallet.AccountOrPerson,
        candidates: [Data]
    ) -> AnyAsyncSequence<Data>

    /// Point-in-time read of which of `candidates` are already minted for `player`.
    /// Used to size the collectibles count up front so it matches what gets streamed.
    func fetchMintedHashes(
        player: GamePallet.AccountOrPerson,
        candidates: [Data]
    ) async throws -> [Data]

    /// Point-in-time read of the player's PENDING (not-yet-confirmed) collectible
    /// hashes from on-chain `nftCandidates` — the chain's real hashes, the same
    /// source the Collectibles/Pocket screen reads. Used to complete the pack on
    /// pass without guessing the attester (account vs person) form.
    func fetchPendingHashes(
        player: GamePallet.AccountOrPerson
    ) async throws -> [Data]

    func fetchDidAttend(
        player: GamePallet.AccountOrPerson,
        gameIndex: GamePallet.GameIndex
    ) async throws -> Bool

    func cancel()
}

final class GameNftsSubscriptionService: GameNftsSubscriptionServicing {
    private let chainRegistry: ChainRegistryProtocol
    private let chainId: ChainModel.Id
    private let logger: LoggerProtocol

    init(
        chainRegistry: ChainRegistryProtocol,
        chainId: ChainModel.Id,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.chainRegistry = chainRegistry
        self.chainId = chainId
        self.logger = logger
    }

    func observeMints(
        player: GamePallet.AccountOrPerson,
        candidates: [Data]
    ) -> AnyAsyncSequence<Data> {
        guard !candidates.isEmpty else {
            return AsyncStream<Data> { $0.finish() }.eraseToAnyAsyncSequence()
        }

        let mappingKeyByHex: [String: Data] = Dictionary(
            uniqueKeysWithValues: candidates.map { ($0.toHex(), $0) }
        )
        let logger = logger
        let totalCandidates = candidates.count

        do {
            let connection = try chainRegistry.getConnectionOrError(for: chainId)
            let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)

            let requests = candidates.map { hash in
                BatchStorageSubscriptionRequest(
                    innerRequest: DoubleMapSubscriptionRequest(
                        storagePath: GamePallet.nfts,
                        localKey: "",
                        keyParamClosure: {
                            (player, BytesCodable(wrappedValue: hash))
                        }
                    ),
                    mappingKey: hash.toHex()
                )
            }

            logger.debug("[GameDebug] nfts subscription START candidates=\(candidates.count)")

            let upstream: AnyAsyncSequence<BatchStorageSubscriptionRawResult>
            upstream = CallbackBatchStorageSubscription.asyncStream(
                requests: requests,
                connection: connection,
                runtimeService: runtimeProvider,
                logger: nil
            )

            let dedupe = SeenSet()
            return AsyncStream<Data> { continuation in
                let task = Task {
                    do {
                        for try await raw in upstream {
                            for entry in raw.values {
                                if case .null = entry.value { continue }
                                guard let mappingKey = entry.mappingKey,
                                      let candidate = mappingKeyByHex[mappingKey]
                                else { continue }
                                if dedupe.insert(candidate) {
                                    logger
                                        .debug(
                                            "[GameDebug] nfts subscription EMIT candidate=\(candidate.toHex()) " +
                                                "totalEmitted=\(dedupe.count)/\(totalCandidates)"
                                        )
                                    continuation.yield(candidate)
                                }
                            }
                        }
                    } catch {
                        logger.error("[GameDebug] nfts subscription error: \(error)")
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in
                    logger.debug("[GameDebug] nfts subscription TERMINATE")
                    task.cancel()
                }
            }
            .eraseToAnyAsyncSequence()
        } catch {
            logger.error("[GameDebug] nfts subscription setup FAILED: \(error)")
            return AsyncStream<Data> { $0.finish() }.eraseToAnyAsyncSequence()
        }
    }

    func fetchMintedHashes(
        player: GamePallet.AccountOrPerson,
        candidates: [Data]
    ) async throws -> [Data] {
        guard !candidates.isEmpty else { return [] }

        let connection = try chainRegistry.getConnectionOrError(for: chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        let requestFactory = StorageRequestFactory.asyncInit()

        let owned: [GamePallet.NftsKey: StringScaleMapper<UInt32>] = try await requestFactory.queryByPrefix(
            engine: connection,
            request: MapRemoteStorageRequest(storagePath: GamePallet.nfts) { player },
            storagePath: GamePallet.nfts,
            factory: { codingFactory },
            options: StorageQueryListOptions(atBlock: nil)
        )
        .asyncExecute()

        let ownedHexes = Set(owned.keys.map { $0.hash.toHex() })
        let minted = candidates.filter { ownedHexes.contains($0.toHex()) }

        logger.debug(
            "[GameDebug] fetchMintedHashes candidates=\(candidates.count) "
                + "ownedNfts=\(owned.count) minted=\(minted.count)"
        )
        return minted
    }

    func fetchPendingHashes(
        player: GamePallet.AccountOrPerson
    ) async throws -> [Data] {
        let connection = try chainRegistry.getConnectionOrError(for: chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        let requestFactory = StorageRequestFactory.asyncInit()

        let pending: [GamePallet.NftKey: IgnoredStorageValue] = try await requestFactory.queryByPrefix(
            engine: connection,
            request: MapRemoteStorageRequest(storagePath: GamePallet.nftCandidates) { player },
            storagePath: GamePallet.nftCandidates,
            factory: { codingFactory },
            options: StorageQueryListOptions(atBlock: nil)
        )
        .asyncExecute()

        let hashes = pending.keys.map(\.hash)
        logger.debug("[GameDebug] fetchPendingHashes → pending=\(hashes.count)")
        return hashes
    }

    func fetchDidAttend(
        player: GamePallet.AccountOrPerson,
        gameIndex: GamePallet.GameIndex
    ) async throws -> Bool {
        let connection = try chainRegistry.getConnectionOrError(for: chainId)
        let runtimeProvider = try chainRegistry.getRuntimeProviderOrError(for: chainId)
        let codingFactory = try await runtimeProvider.fetchCoderFactoryOperation().asyncExecute()
        let requestFactory = StorageRequestFactory.asyncInit()

        let responses: [StorageResponse<[StringScaleMapper<GamePallet.GameIndex>]>] =
            try await requestFactory.queryItems(
                engine: connection,
                keyParams: { [player] },
                factory: { codingFactory },
                storagePath: GamePallet.playerAttendanceHistory,
                at: nil
            )
            .asyncExecute()

        let attendedGames = responses.first?.value?.map(\.value) ?? []
        let didAttend = attendedGames.contains(gameIndex)
        logger.debug(
            "[GameDebug] fetchDidAttend gameIndex=\(gameIndex) "
                + "attended=\(attendedGames) result=\(didAttend)"
        )
        return didAttend
    }

    func cancel() {}
}

private final class SeenSet {
    private var values: Set<Data> = []
    var count: Int { values.count }

    func insert(_ value: Data) -> Bool {
        values.insert(value).inserted
    }
}

private struct IgnoredStorageValue: Decodable {
    init(from _: Decoder) throws {}
}
