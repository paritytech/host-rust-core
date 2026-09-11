import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import Individuality

struct GameAttestationCandidates {
    let hashes: [Data]
    let expectedPeerRounds: Int
}

protocol GameGroupRosterProviding {
    func fetchAttestationCandidates(
        gameIndex: GamePallet.GameIndex,
        attestee: GamePallet.AccountOrPerson,
        maxGroupSize: UInt,
        playerCount: UInt,
        blockHash: Data?
    ) async throws -> GameAttestationCandidates
}

final class GameGroupRosterService: GameGroupRosterProviding {
    private let connection: JSONRPCEngine
    private let runtimeService: RuntimeCodingServiceProtocol
    private let requestFactory = StorageRequestFactory.asyncInit()

    init(connection: JSONRPCEngine, runtimeService: RuntimeCodingServiceProtocol) {
        self.connection = connection
        self.runtimeService = runtimeService
    }

    func fetchAttestationCandidates(
        gameIndex: GamePallet.GameIndex,
        attestee: GamePallet.AccountOrPerson,
        maxGroupSize: UInt,
        playerCount: UInt,
        blockHash: Data?
    ) async throws -> GameAttestationCandidates {
        guard maxGroupSize > 0, playerCount > 0 else {
            Logger.shared
                .debug(
                    "[GameDebug] roster: skip — maxGroupSize=\(maxGroupSize) playerCount=\(playerCount)"
                )
            return GameAttestationCandidates(hashes: [], expectedPeerRounds: 0)
        }

        let codingFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        let myIndices = try await fetchPlayerIndices(
            attestee: attestee,
            codingFactory: codingFactory,
            blockHash: blockHash
        )
        let attesteeEncoder = ScaleEncoder()
        try attestee.encode(scaleEncoder: attesteeEncoder)
        let attesteeBytes = attesteeEncoder.encode()
        Logger.shared
            .debug(
                "[GameDebug] roster: PlayerToIndex(me) = \(myIndices) " +
                    "(attestee variant=\(attestee.rawTypeValue) bytes=\(attesteeBytes.toHex()))"
            )
        guard !myIndices.isEmpty else {
            Logger.shared.debug("[GameDebug] roster: PlayerToIndex empty for attestee — drained?")
            return GameAttestationCandidates(hashes: [], expectedPeerRounds: 0)
        }

        let peerKeysByRound = buildPeerKeys(
            myIndices: myIndices,
            maxGroupSize: maxGroupSize,
            playerCount: playerCount
        )
        Logger.shared
            .debug(
                "[GameDebug] roster: peer keys to fetch count=\(peerKeysByRound.count) " +
                    "keys=\(peerKeysByRound.map { "(r:\($0.round),i:\($0.key.playerIndex))" })"
            )
        guard !peerKeysByRound.isEmpty else {
            return GameAttestationCandidates(hashes: [], expectedPeerRounds: 0)
        }

        let peerLookups = try await fetchPeers(
            keys: peerKeysByRound.map(\.key),
            codingFactory: codingFactory,
            blockHash: blockHash
        )

        var hashes: [Data] = []
        for (idx, response) in peerLookups.enumerated() {
            guard let peer = response.value else {
                Logger.shared.debug("[GameDebug] roster: missing peer for key \(peerKeysByRound[idx].key)")
                continue
            }
            let round = peerKeysByRound[idx].round
            let peerEncoder = ScaleEncoder()
            try peer.encode(scaleEncoder: peerEncoder)
            let peerBytes = peerEncoder.encode()
            Logger.shared
                .debug(
                    "[GameDebug] roster: peer for (round=\(round), peerIdx=\(peerKeysByRound[idx].key.playerIndex)) " +
                        "variant=\(peer.rawTypeValue) bytes=\(peerBytes.toHex())"
                )

            let peerAccountBytes: Data =
                switch peer {
                case let .account(accountId):
                    accountId
                case let .person(alias):
                    alias
                }
            let peerAsAccount = GamePallet.AccountOrPerson.account(accountID: peerAccountBytes)
            let peerAsPerson = GamePallet.AccountOrPerson.person(alias: peerAccountBytes)

            let hashAccount = try AttestationHashCalculator.computeNftHash(
                gameIndex: gameIndex,
                round: round,
                attester: peerAsAccount,
                attestee: attestee
            )
            let hashPerson = try AttestationHashCalculator.computeNftHash(
                gameIndex: gameIndex,
                round: round,
                attester: peerAsPerson,
                attestee: attestee
            )
            Logger.shared
                .debug(
                    "[GameDebug] roster: hashes for round=\(round) " +
                        "peerIdx=\(peerKeysByRound[idx].key.playerIndex):\n" +
                        "  attesterAccount → \(hashAccount.toHex())\n" +
                        "  attesterPerson  → \(hashPerson.toHex())"
                )
            hashes.append(hashAccount)
            hashes.append(hashPerson)
        }

        Logger.shared
            .debug(
                "[GameDebug] roster: derived \(hashes.count) candidate hashes (rounds=\(myIndices.count) " +
                    "maxGroupSize=\(maxGroupSize) playerCount=\(playerCount) " +
                    "peerRounds=\(peerKeysByRound.count))\n" +
                    "candidateHashes=\(hashes.map { $0.toHex() })"
            )
        return GameAttestationCandidates(
            hashes: hashes,
            expectedPeerRounds: peerKeysByRound.count
        )
    }
}

private extension GameGroupRosterService {
    struct KeyedRound {
        let key: GamePallet.IndexToPlayerKey
        let round: GamePallet.RoundIndex
    }

    func fetchPlayerIndices(
        attestee: GamePallet.AccountOrPerson,
        codingFactory: RuntimeCoderFactoryProtocol,
        blockHash: Data?
    ) async throws -> [GamePallet.PlayerIndex] {
        let responses: [StorageResponse<[StringCodable<GamePallet.PlayerIndex>]>] = try await requestFactory
            .queryItems(
                engine: connection,
                keyParams: { [attestee] },
                factory: { codingFactory },
                storagePath: GamePallet.playerToIndex,
                at: blockHash
            )
            .asyncExecute()

        return responses.first?.value?.map(\.wrappedValue) ?? []
    }

    func buildPeerKeys(
        myIndices: [GamePallet.PlayerIndex],
        maxGroupSize: UInt,
        playerCount: UInt
    ) -> [KeyedRound] {
        let numberOfGroups = UInt((Double(playerCount) / Double(maxGroupSize)).rounded(.up))
        guard numberOfGroups > 0 else { return [] }

        var keys: [KeyedRound] = []
        for (roundIndex, myIdx) in myIndices.enumerated() {
            let round = GamePallet.RoundIndex(roundIndex)
            let myU = UInt(myIdx)
            let groupIndex = myU % numberOfGroups

            for slot in 0 ..< maxGroupSize {
                let peerIdx = groupIndex + slot * numberOfGroups
                if peerIdx >= playerCount { continue }
                if peerIdx == myU { continue }
                let key = GamePallet.IndexToPlayerKey(
                    roundIndex: round,
                    playerIndex: GamePallet.PlayerIndex(peerIdx)
                )
                keys.append(KeyedRound(key: key, round: round))
            }
        }
        return keys
    }

    func fetchPeers(
        keys: [GamePallet.IndexToPlayerKey],
        codingFactory: RuntimeCoderFactoryProtocol,
        blockHash: Data?
    ) async throws -> [StorageResponse<GamePallet.AccountOrPerson>] {
        try await requestFactory.queryItems(
            engine: connection,
            keyParams: { keys },
            factory: { codingFactory },
            storagePath: GamePallet.indexToPlayer,
            at: blockHash
        )
        .asyncExecute()
    }
}
