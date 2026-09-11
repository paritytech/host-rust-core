import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct GameHistorySubscriptionResult: BatchStorageSubscriptionResult {
    enum Key: String {
        case globalGameIndex
        case attendanceHistory
        case player
        case archivedPlayer
        case game
    }

    let globalGameIndex: UncertainStorage<GamePallet.GameIndex?>
    let attendanceHistory: UncertainStorage<Set<GamePallet.GameIndex>?>
    let player: UncertainStorage<GamePallet.Player?>
    let archivedPlayer: UncertainStorage<GamePallet.ArchivedPlayer?>
    let game: UncertainStorage<GamePallet.GameInfo?>
    let blockHash: Data?

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        globalGameIndex = try UncertainStorage<StringScaleMapper<GamePallet.GameIndex>?>(
            values: values,
            mappingKey: Key.globalGameIndex.rawValue,
            context: context
        )
        .map { $0?.value }

        attendanceHistory = try UncertainStorage<[StringCodable<GamePallet.GameIndex>]?>(
            values: values,
            mappingKey: Key.attendanceHistory.rawValue,
            context: context
        )
        .map {
            guard let array = $0?.map(\.wrappedValue) else {
                return nil
            }
            return Set(array)
        }

        player = try UncertainStorage(
            values: values,
            mappingKey: Key.player.rawValue,
            context: context
        )

        archivedPlayer = try UncertainStorage(
            values: values,
            mappingKey: Key.archivedPlayer.rawValue,
            context: context
        )

        game = try UncertainStorage(
            values: values,
            mappingKey: Key.game.rawValue,
            context: context
        )

        blockHash = try blockHashJson.map(to: Data?.self, with: context)
    }
}

struct GameHistorySyncData {
    let globalGameIndex: GamePallet.GameIndex?
    let attendanceHistory: Set<GamePallet.GameIndex>?
    let player: GamePallet.Player?
    let archivedPlayer: GamePallet.ArchivedPlayer?
    let game: GamePallet.GameInfo?
    let actualGameDates: ActualGameDatesByIndex?
    let blockHash: Data?

    var firstGame: GamePallet.GameIndex? {
        let playerValue = player?.firstGame
        let archivedValue = archivedPlayer?.firstGame

        switch (playerValue, archivedValue) {
        case let (.some(value1), .some(value2)):
            return min(value1, value2)
        case let (.some(value1), .none):
            return value1
        case let (.none, .some(value2)):
            return value2
        case (.none, .none):
            return nil
        }
    }

    var range: ClosedRange<GamePallet.GameIndex>? {
        guard
            let globalGameIndex,
            let firstGame,
            firstGame <= globalGameIndex
        else {
            return nil
        }
        return firstGame ... globalGameIndex
    }
}

extension GameHistorySyncData {
    init() {
        globalGameIndex = nil
        attendanceHistory = nil
        player = nil
        archivedPlayer = nil
        game = nil
        actualGameDates = nil
        blockHash = nil
    }

    func applying(_ result: GameHistorySubscriptionResult) -> GameHistorySyncData {
        GameHistorySyncData(
            globalGameIndex: result.globalGameIndex.valueWhenDefined(else: globalGameIndex),
            attendanceHistory: result.attendanceHistory.valueWhenDefined(else: attendanceHistory),
            player: result.player.valueWhenDefined(else: player),
            archivedPlayer: result.archivedPlayer.valueWhenDefined(else: archivedPlayer),
            game: result.game.valueWhenDefined(else: game),
            actualGameDates: actualGameDates,
            blockHash: result.blockHash
        )
    }

    func applying(_ actualGameDates: ActualGameDatesByIndex?) -> GameHistorySyncData {
        GameHistorySyncData(
            globalGameIndex: globalGameIndex,
            attendanceHistory: attendanceHistory,
            player: player,
            archivedPlayer: archivedPlayer,
            game: game,
            actualGameDates: actualGameDates,
            blockHash: blockHash
        )
    }
}
