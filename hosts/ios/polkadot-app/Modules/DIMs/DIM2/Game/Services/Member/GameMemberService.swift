import Foundation
import SubstrateSdk
import SubstrateStorageQuery
import StructuredConcurrency
import Individuality

struct GameMemberInfo: Equatable {
    /// `recognition.is_recognized()` — the runtime's check for choosing the airdrop proof variant
    /// (Alias for recognized, Account for non-recognized).
    let isRecognized: Bool
    /// `is_recognized() || reached_personhood` — the claim-eligibility signal (used by the prize gate).
    let hasReachedPersonhood: Bool
}

protocol GameMemberServicing {
    func fetchMemberInfo(
        player: GamePallet.AccountOrPerson,
        blockHash: Data?
    ) async throws -> GameMemberInfo?
}

final class GameMemberService: GameMemberServicing {
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

    func fetchMemberInfo(
        player: GamePallet.AccountOrPerson,
        blockHash: Data?
    ) async throws -> GameMemberInfo? {
        Logger.shared
            .debug(
                "[GameDebug] member.fetchMemberInfo start player=\(player.rawTypeValue) " +
                    "blockHash=\(blockHash?.toHex() ?? "head")"
            )

        let codingFactory = try await runtimeService.fetchCoderFactoryOperation().asyncExecute()

        let responses: [StorageResponse<ScorePallet.Participant>] = try await requestFactory.queryItems(
            engine: connection,
            keyParams: { [player] },
            factory: { codingFactory },
            storagePath: ScorePallet.participants,
            at: blockHash
        )
        .asyncExecute()

        Logger.shared.debug("[GameDebug] member queryItems returned count=\(responses.count)")

        guard let participant = responses.first?.value else {
            Logger.shared.debug("[GameDebug] member.fetchMemberInfo: no participant entry — returning nil")
            return nil
        }

        let isRecognized = participant.recognition.isRecognized
        let hasReachedPersonhood = isRecognized || participant.reachedPersonhood
        Logger.shared
            .debug(
                "[GameDebug] member participant isRecognized=\(isRecognized) " +
                    "hasReachedPersonhood=\(hasReachedPersonhood) " +
                    "recognition=\(participant.recognition) reachedPersonhood=\(participant.reachedPersonhood)"
            )
        return GameMemberInfo(isRecognized: isRecognized, hasReachedPersonhood: hasReachedPersonhood)
    }
}
