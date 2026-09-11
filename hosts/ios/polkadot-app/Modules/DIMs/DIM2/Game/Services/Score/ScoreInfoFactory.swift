import Foundation
import Individuality

protocol ScoreInfoMaking {
    func makeScoreInfo(
        syncData: ScoreInfoSyncData?
    ) -> ScoreInfo?
}

final class ScoreInfoFactory {}

extension ScoreInfoFactory: ScoreInfoMaking {
    func makeScoreInfo(
        syncData: ScoreInfoSyncData?
    ) -> ScoreInfo? {
        guard
            let syncData,
            let requiredScore = syncData.requiredScore
        else {
            return nil
        }

        let score = makeScore(participant: syncData.participant)

        return .init(
            score: score,
            streak: syncData.participant?.streak.makeIntegerStreak(),
            requiredScore: Int(requiredScore),
            credit: syncData.participant?.credit,
            isParticipant: syncData.participant != nil,
            isRegistrableParticipant: syncData.participant?.reachedPersonhood == true,
            isSuspended: syncData.participant?.recognition.isSuspended == true,
            isExternallyRecognized: syncData.participant?.recognition == .externallyRecognized
        )
    }
}

private extension ScoreInfoFactory {
    func makeScore(participant: ScorePallet.Participant?) -> Int? {
        guard let participant else {
            return nil
        }
        return Int(participant.score)
    }
}
