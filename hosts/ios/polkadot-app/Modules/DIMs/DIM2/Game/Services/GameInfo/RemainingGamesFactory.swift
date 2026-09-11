import Foundation
import Individuality

protocol RemainingGamesMaking {
    func makeResult(input: RemainingGamesInput) -> RemainingGamesResult
}

final class RemainingGamesFactory {}

extension RemainingGamesFactory: RemainingGamesMaking {
    func makeResult(input: RemainingGamesInput) -> RemainingGamesResult {
        var gamesNeeded = 0
        var index = -1
        var simulatedScore = input.currentScore
        var simulatedStreak = max(0, input.currentStreak)

        repeat {
            gamesNeeded += 1
            index += 1
            simulatedStreak += 1
            simulatedScore += simulatedStreak
        } while simulatedScore < targetScore(from: input, for: index)

        return .init(
            currentScore: input.currentScore,
            targetScore: targetScore(from: input, for: gamesNeeded),
            gamesLeft: gamesNeeded,
            personhoodState: input.participant?.personhoodState ?? .unknown
        )
    }

    private func targetScore(from input: RemainingGamesInput, for index: Int) -> Int {
        if index == 0 {
            return input.overridedCurrentGameScore ?? input.requiredScore
        }
        if let scores = input.overridedScheduledGameScores, index - 1 < scores.count {
            return scores[index - 1] ?? input.requiredScore
        }
        return input.requiredScore
    }
}

struct RemainingGamesInput {
    let participant: ScorePallet.Participant?
    let currentScore: Int
    let currentStreak: Int
    let requiredScore: Int
    let overridedCurrentGameScore: Int?
    let overridedScheduledGameScores: [Int?]?
}

struct RemainingGamesResult {
    let currentScore: Int
    let targetScore: Int
    let gamesLeft: Int
    let personhoodState: GameResultsMessageDecoder.GameResult.PersonhoodState
}

private extension ScorePallet.Participant {
    var personhoodState: GameResultsMessageDecoder.GameResult.PersonhoodState {
        guard recognition != .externallyRecognized else {
            return .externallyRecognized
        }

        guard !reachedPersonhood else {
            return .reachedPersonhood
        }

        return .playing(suspended: recognition.isSuspended)
    }
}
