import Foundation
import Individuality
import Products

enum GameReminderTarget: Equatable {
    case game(GamePallet.GameIndex)
    case product(ProductId)
}

/// Separate keys let the native and product game reminders coexist without cancelling each other.
struct GameReminderStorageKeys {
    let alarmId: SettingsKey
    let alarmFireDate: SettingsKey
    let notificationDate: SettingsKey
    let notificationIdentifier: String

    static let game = GameReminderStorageKeys(
        alarmId: .gameAlarmId,
        alarmFireDate: .gameAlarmFireDate,
        notificationDate: .gameStartNotificationDate,
        notificationIdentifier: "game_start"
    )

    static let product = GameReminderStorageKeys(
        alarmId: .productGameAlarmId,
        alarmFireDate: .productGameAlarmFireDate,
        notificationDate: .productGameStartNotificationDate,
        notificationIdentifier: "product_game_start"
    )
}

protocol GameStartReminderServicing {
    func scheduleReminder(gameDate: Date, target: GameReminderTarget, timingSeconds: Int)
    func cancelReminder()
}
