import Foundation
import Individuality

protocol GameScheduleMaking {
    func makeGameSchedule(
        syncData: GameScheduleSyncData?
    ) -> GameSchedule?
}

final class GameScheduleFactory {}

extension GameScheduleFactory: GameScheduleMaking {
    func makeGameSchedule(
        syncData: GameScheduleSyncData?
    ) -> GameSchedule? {
        guard
            let syncData,
            let schedules = syncData.gameSchedules,
            let constantDurationValues = syncData.constantDurationValues
        else {
            return nil
        }

        let durationValues = syncData.testnetDurationValues ?? constantDurationValues

        let untilRegistrationCloses = TimeInterval(durationValues.shuffle)
            + TimeInterval(durationValues.postShuffleMargin)
        let untilRegistrationOpens = TimeInterval(durationValues.registration) + untilRegistrationCloses

        let items = schedules.compactMap {
            makeItem(
                gameSchedule: $0,
                untilRegistrationOpens: untilRegistrationOpens,
                untilRegistrationCloses: untilRegistrationCloses
            )
        }

        return .init(items: items)
    }
}

private extension GameScheduleFactory {
    func makeItem(
        gameSchedule: GamePallet.GameSchedule,
        untilRegistrationOpens: TimeInterval,
        untilRegistrationCloses: TimeInterval
    ) -> GameSchedule.Item? {
        guard gameSchedule.gamePlayTime > 0 else {
            return nil
        }

        let gameStartDate = Date(timeIntervalSince1970: TimeInterval(gameSchedule.gamePlayTime))
        let registrationStartDate = gameStartDate.addingTimeInterval(-untilRegistrationOpens)
        let registrationEndDate = gameStartDate.addingTimeInterval(-untilRegistrationCloses)

        return .init(
            registrationStartDate: registrationStartDate,
            registrationEndDate: registrationEndDate,
            gameStartDate: gameStartDate,
            requiredScoreOverride: gameSchedule.personhoodScoreOverride.map { Int($0) }
        )
    }
}
