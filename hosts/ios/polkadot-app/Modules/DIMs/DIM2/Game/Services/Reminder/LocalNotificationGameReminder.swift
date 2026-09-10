import Foundation
import UserNotifications
import Keystore_iOS
import Individuality

final class LocalNotificationGameReminder {
    private let localNotificationService: UserNotificationServicing
    private let settingsManager: SettingsManagerProtocol
    private let logger: LoggerProtocol

    private static let notificationIdentifier = "game_start"

    init(
        localNotificationService: UserNotificationServicing,
        settingsManager: SettingsManagerProtocol,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.localNotificationService = localNotificationService
        self.settingsManager = settingsManager
        self.logger = logger
    }
}

extension LocalNotificationGameReminder: GameStartReminderServicing {
    func scheduleReminder(gameDate: Date, gameIndex: GamePallet.GameIndex, timingSeconds: Int) {
        localNotificationService.notificationAccessStatus { status in
            guard status == .allowed else {
                return
            }
            self.performScheduleReminder(gameDate: gameDate, gameIndex: gameIndex, timingSeconds: timingSeconds)
        }
    }

    func cancelReminder() {
        cancel()
        settingsManager.removeValue(for: .gameStartNotificationDate)
    }
}

private extension LocalNotificationGameReminder {
    func performScheduleReminder(gameDate: Date, gameIndex: GamePallet.GameIndex, timingSeconds: Int) {
        let notificationDate = Int(gameDate.timeIntervalSinceReferenceDate) - timingSeconds
        let storedDate = settingsManager.integer(for: .gameStartNotificationDate)

        guard notificationDate != storedDate else {
            logger.debug("gameStart date unchanged, skipping reschedule")
            return
        }

        cancel()
        settingsManager.removeValue(for: .gameStartNotificationDate)

        let fireDate = Date(timeIntervalSinceReferenceDate: TimeInterval(notificationDate))

        guard fireDate > Date() else {
            logger.debug("fire date is in the past, skipping")
            return
        }

        settingsManager.set(value: notificationDate, for: .gameStartNotificationDate)

        localNotificationService.scheduleNotification(
            withIdentifier: Self.notificationIdentifier,
            content: makeContent(timingSeconds: timingSeconds, gameIndex: gameIndex),
            after: fireDate.timeIntervalSince(Date())
        ) { [logger] error in
            logger.debug("gameStart scheduled with error: \(String(describing: error))")
        }
    }

    func cancel() {
        localNotificationService.cancelScheduledNotifications(withIdentifiers: [Self.notificationIdentifier])
    }

    func makeContent(timingSeconds: Int, gameIndex: GamePallet.GameIndex) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(
            localized: .Notification.gameNotificationGameStartTitle(String(timingSeconds))
        )
        content.body = String(localized: .Notification.gameNotificationGameStartBody)
        content.sound = UNNotificationSound(named: .init("game_alarm.caf"))
        content.userInfo = [
            PushNotificationKeys.chatExtensionId: DIM2ChatExtension.identifier,
            PushNotificationKeys.pushSource: PushNotificationSource.chat.rawValue,
            PushNotificationKeys.gameState: PushGameNotificationType.start.rawValue,
            PushNotificationKeys.gameIndex: Int(gameIndex)
        ]
        return content
    }
}
