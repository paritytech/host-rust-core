import Foundation
import Individuality

protocol GameInfoMaking {
    func makeGameInfo(
        syncData: GameInfoSyncData?
    ) -> GameInfo?

    func makeIndexToPlayerKeysByRound(
        syncData: GameInfoSyncData?,
        gameInfo: GameInfo?
    ) -> IndexToPlayerKeysByRound
}

final class GameInfoFactory {}

extension GameInfoFactory: GameInfoMaking {
    func makeGameInfo(
        syncData: GameInfoSyncData?
    ) -> GameInfo? {
        guard
            let syncData,
            let game = syncData.game,
            let state = makeGameState(syncData: syncData)
        else {
            return nil
        }

        let registrationEnds: Date? =
            if game.registrationEnds > 0 {
                Date(timeIntervalSince1970: TimeInterval(game.registrationEnds))
            } else {
                nil
            }

        let gameDate: Date? =
            if game.gameDate > 0 {
                Date(timeIntervalSince1970: TimeInterval(game.gameDate))
            } else {
                nil
            }

        let reportingEndDate: Date? =
            if game.reportEnds > 0 {
                Date(timeIntervalSince1970: TimeInterval(game.reportEnds))
            } else {
                nil
            }

        let info = GameInfo(
            state: state,
            index: game.index,
            sortedRounds: makeSortedRounds(syncData: syncData),
            playerCredibility: syncData.player?.credibility,
            isRegistered: syncData.player?.registered == true,
            isReportSent: syncData.player?.sentReport == true,
            registrationEnds: registrationEnds,
            gameDate: gameDate,
            reportingEndDate: reportingEndDate,
            maxGroupSize: UInt(game.maxGroupSize),
            requiredScoreOverride: game.personhoodScoreOverride.map { Int($0) },
            airdropScheduled: (game.airdropsScheduled ?? 0) > 0
        )

        Logger.shared.debug(
            "[GameDebug] GameInfo decode: index=\(game.index) "
                + "airdropsScheduled(raw)=\(String(describing: game.airdropsScheduled))"
        )

        return info
    }

    func makeIndexToPlayerKeysByRound(
        syncData: GameInfoSyncData?,
        gameInfo: GameInfo?
    ) -> IndexToPlayerKeysByRound {
        var indexToPlayerKeysByRound = IndexToPlayerKeysByRound()

        guard
            let gameInfo,
            case let .inProgress(inProgressState) = gameInfo.state,
            case let .inProgress(playerCount, _) = inProgressState,
            let playerIndices = syncData?.playerIndices,
            !playerIndices.isEmpty,
            playerCount > 0,
            gameInfo.maxGroupSize > 0
        else {
            return indexToPlayerKeysByRound
        }

        let groupCount = UInt(ceil(Double(playerCount) / Double(gameInfo.maxGroupSize)))

        for (roundIndex, playerIndex) in playerIndices.enumerated() {
            let roundIndex = GamePallet.RoundIndex(roundIndex)
            let playerIndex = UInt(playerIndex)
            let playerGroupIndex = playerIndex % groupCount

            var indexToPlayerKeys = [GamePallet.IndexToPlayerKey]()

            for counterInGroup in 0 ..< gameInfo.maxGroupSize {
                let indexInGroup = playerGroupIndex + (counterInGroup * groupCount)

                if indexInGroup < playerCount {
                    indexToPlayerKeys.append(GamePallet.IndexToPlayerKey(
                        roundIndex: roundIndex,
                        playerIndex: UInt32(indexInGroup)
                    ))
                }
            }

            indexToPlayerKeysByRound[roundIndex] = indexToPlayerKeys
        }

        return indexToPlayerKeysByRound
    }
}

private extension GameInfoFactory {
    func makeGameState(syncData: GameInfoSyncData) -> GameState? {
        guard let game = syncData.game else {
            return nil
        }

        switch game.state {
        case .registration:
            return .registration
        case .shuffle:
            return .shuffle
        case let .reporting(playerCount):
            return .inProgress(makeInProgressState(
                syncData: syncData,
                playerCount: playerCount,
                maxGroupSize: game.maxGroupSize
            ))
        case .playerProcess:
            return .processing
        case .cancelling:
            return .cancelling
        }
    }

    func makeInProgressState(
        syncData: GameInfoSyncData,
        playerCount: UInt32,
        maxGroupSize: UInt32
    ) -> GameInProgressState {
        guard
            syncData.game != nil,
            syncData.player?.registered == true
        else {
            return .notRegistered
        }

        let gameplayGroupSize = GameGroupSettings(
            preferredMaxGroupSize: UInt(maxGroupSize),
            numberOfPlayers: UInt(playerCount)
        ).getMaxGroupSize()

        return .inProgress(
            playerCount: Int(playerCount),
            gameplayGroupSize: gameplayGroupSize
        )
    }

    func makeSortedRounds(syncData: GameInfoSyncData) -> [GameRound] {
        guard
            let playersByRound = syncData.playersByRound,
            !playersByRound.isEmpty
        else {
            return []
        }

        var rounds = [GameRound]()

        let sortedPlayerLists = playersByRound
            .sorted { $0.key < $1.key }

        for players in sortedPlayerLists {
            rounds.append(GameRound(players: players.value))
        }

        return rounds
    }
}
