import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct GameInfoSubscriptionResult: BatchStorageSubscriptionResult {
    enum Key: String {
        case game
        case player
        case playerIndices
    }

    let game: UncertainStorage<GamePallet.GameInfo?>
    let player: UncertainStorage<GamePallet.Player?>
    let playerIndices: UncertainStorage<[GamePallet.PlayerIndex]?>
    let blockHash: Data?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        game = try UncertainStorage(
            values: values,
            mappingKey: Key.game.rawValue,
            context: context
        )

        player = try UncertainStorage(
            values: values,
            mappingKey: Key.player.rawValue,
            context: context
        )

        playerIndices = try UncertainStorage<[StringCodable<GamePallet.PlayerIndex>]?>(
            values: values,
            mappingKey: Key.playerIndices.rawValue,
            context: context
        )
        .map { $0?.map(\.wrappedValue) }

        blockHash = try blockHashJson.map(to: Data?.self, with: context)
    }
}

struct GameInfoSyncData {
    let game: GamePallet.GameInfo?
    let player: GamePallet.Player?
    let playerIndices: [GamePallet.PlayerIndex]?
    let playersByRound: PlayersByRound?
}

extension GameInfoSyncData {
    init() {
        game = nil
        player = nil
        playerIndices = nil
        playersByRound = nil
    }

    func applying(_ result: GameInfoSubscriptionResult) -> GameInfoSyncData {
        GameInfoSyncData(
            game: result.game.valueWhenDefined(else: game),
            player: result.player.valueWhenDefined(else: player),
            playerIndices: result.playerIndices.valueWhenDefined(else: playerIndices),
            playersByRound: playersByRound
        )
    }

    func applying(_ playersByRound: PlayersByRound) -> GameInfoSyncData {
        GameInfoSyncData(
            game: game,
            player: player,
            playerIndices: playerIndices,
            playersByRound: playersByRound
        )
    }
}
