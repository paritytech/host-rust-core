import Foundation
import Individuality

protocol GameStartReminderServicing {
    func scheduleReminder(gameDate: Date, gameIndex: GamePallet.GameIndex, timingSeconds: Int)
    func cancelReminder()
}
