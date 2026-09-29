import Foundation
import SubstrateSdk
import Individuality

struct GameInfo: Equatable {
    let state: GameState
    let index: GamePallet.GameIndex
    let sortedRounds: [GameRound]
    let playerCredibility: GamePallet.PlayerCredibility?
    let isRegistered: Bool
    let isReportSent: Bool
    let registrationEnds: Date?
    let gameDate: Date?
    let reportingEndDate: Date?
    let maxGroupSize: UInt
    let requiredScoreOverride: Int?
    let airdropScheduled: Bool

    // User has played previous game
    var isCrediblePlayer: Bool {
        playerCredibility != nil
    }
}

enum GameState: Equatable {
    case registration
    case shuffle
    case inProgress(GameInProgressState)
    case processing
    case cancelling
}

enum GameInProgressState: Equatable {
    case notRegistered

    case inProgress(
        playerCount: Int,
        gameplayGroupSize: UInt
    )
}

struct GameRound: Equatable {
    let players: [AccountId]
}

extension GameState {
    var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }
}

extension GameInfo {
    func isGameRoomAvailable(
        now: Date = .now,
        availabilityInterval: TimeInterval
    ) -> Bool {
        guard
            isReportSent != true,
            isRegistered,
            let gameDate,
            gameDate.timeIntervalSince(now) <= availabilityInterval
        else {
            return false
        }

        switch state {
        case .registration,
             .shuffle,
             .inProgress:
            return true
        case .processing,
             .cancelling:
            return false
        }
    }

    func players(for roundIndex: GamePallet.RoundIndex) -> [AccountId]? {
        guard sortedRounds.count > roundIndex else {
            return nil
        }
        return sortedRounds[Int(roundIndex)].players
    }
}
