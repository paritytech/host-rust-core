import Foundation
import Foundation_iOS
import SubstrateSdk
import SubstrateStorageSubscription
import Individuality

struct GameScheduleSubscriptionResult: BatchStorageSubscriptionResult {
    enum Key: String {
        case gameSchedules
        case testnetDurationValues
    }

    let gameSchedules: UncertainStorage<[GamePallet.GameSchedule]?>
    let testnetDurationValues: UncertainStorage<GamePallet.PhaseDurationValues?>

    init(
        values: [BatchStorageSubscriptionResultValue],
        blockHashJson _: JSON,
        context: [CodingUserInfoKey: Any]?
    ) throws {
        gameSchedules = try UncertainStorage(
            values: values,
            mappingKey: Key.gameSchedules.rawValue,
            context: context
        )

        testnetDurationValues = try UncertainStorage(
            values: values,
            mappingKey: Key.testnetDurationValues.rawValue,
            context: context
        )
    }
}

struct GameScheduleSyncData {
    let gameSchedules: [GamePallet.GameSchedule]?
    let constantDurationValues: GamePallet.PhaseDurationValues?
    let testnetDurationValues: GamePallet.PhaseDurationValues?
}

extension GameScheduleSyncData {
    init() {
        gameSchedules = nil
        constantDurationValues = nil
        testnetDurationValues = nil
    }

    func applying(_ result: GameScheduleSubscriptionResult) -> GameScheduleSyncData {
        GameScheduleSyncData(
            gameSchedules: result.gameSchedules.valueWhenDefined(else: gameSchedules),
            constantDurationValues: constantDurationValues,
            testnetDurationValues: result.testnetDurationValues.valueWhenDefined(else: testnetDurationValues)
        )
    }

    func applying(constantDurationValues: GamePallet.PhaseDurationValues) -> GameScheduleSyncData {
        GameScheduleSyncData(
            gameSchedules: gameSchedules,
            constantDurationValues: constantDurationValues,
            testnetDurationValues: testnetDurationValues
        )
    }
}
