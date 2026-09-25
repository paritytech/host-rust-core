import AlarmKit
import Foundation
import Products
import SwiftUI
import UserNotifications

/// Asks the OS to reach the user at a reminder's fire date.
protocol GameReminderDelivering: Sendable {
    /// Schedule the alarm or notification. `nil` when the OS allows neither, or when the fire date has passed.
    func deliver(productId: ProductId, firingAt fireDate: Date) async -> GameReminderDelivery?
    /// Cancel a scheduled alarm or notification. Cancelling one that already fired or never existed is a no-op.
    func withdraw(_ delivery: GameReminderDelivery) async
}

/// The link that opens a product through the app's own deeplink handling.
enum GameReminderProductLink {
    /// The product's universal link, derived from its dot-domain `productId`.
    static func url(for productId: ProductId) -> URL? {
        ProductHost.name(fromDotDomain: productId).flatMap(AppConfig.ProductUniversalLink.url(for:))
    }
}

/// The fallback notification: the alarm's title and body, the game tone, and a tap that opens the product.
enum GameReminderNotificationContent {
    /// Builds the notification content that routes a tap to `productId`'s product.
    static func make(productId: ProductId) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = String(
            localized: .Notification.gameNotificationGameStartTitle(String(Int(GameReminderTiming.alarmLeadTime)))
        )
        content.body = String(localized: .Notification.gameNotificationGameStartBody)
        content.sound = UNNotificationSound(named: .init("game_alarm.caf"))
        var userInfo: [String: Any] = [
            PushNotificationKeys.pushSource: PushNotificationSource.products.rawValue
        ]
        if let link = GameReminderProductLink.url(for: productId) {
            userInfo[PushNotificationKeys.deeplink] = link.absoluteString
        }
        content.userInfo = userInfo
        return content
    }
}

/// Rings an AlarmKit alarm on iOS 26.1+ when alarms are authorized, and otherwise schedules the fallback
/// notification when notifications are allowed.
///
/// `@unchecked Sendable`: all stored state is immutable after `init`, and `UserNotificationServicing`
/// conformers are safe to call from any thread.
final class SystemGameReminderDelivery: GameReminderDelivering, @unchecked Sendable {
    private let notificationService: UserNotificationServicing
    private let alarmsAvailable: @Sendable () -> Bool
    private let logger: LoggerProtocol

    init(
        notificationService: UserNotificationServicing = UserNotificationService.shared,
        alarmsAvailable: @escaping @Sendable () -> Bool = SystemGameReminderDelivery.alarmKitAuthorized,
        logger: LoggerProtocol = Logger.shared
    ) {
        self.notificationService = notificationService
        self.alarmsAvailable = alarmsAvailable
        self.logger = logger
    }

    /// Whether AlarmKit is available and authorized on this OS version.
    static func alarmKitAuthorized() -> Bool {
        if #available(iOS 26.1, *) {
            return AlarmManager.shared.authorizationState == .authorized
        }
        return false
    }

    func deliver(productId: ProductId, firingAt fireDate: Date) async -> GameReminderDelivery? {
        guard fireDate > Date() else {
            return nil
        }

        if alarmsAvailable(), #available(iOS 26.1, *) {
            let alarmId = UUID()
            do {
                try await scheduleAlarm(id: alarmId, productId: productId, fireDate: fireDate)
                return .alarm(alarmId)
            } catch {
                logger.error("Game reminder alarm for \(productId) failed: \(error)")
            }
        }

        guard await notificationService.notificationAccessStatus() == .allowed else {
            return nil
        }

        let identifier = "game:\(productId)"
        do {
            try await notificationService.scheduleNotification(
                withIdentifier: identifier,
                content: GameReminderNotificationContent.make(productId: productId),
                after: fireDate.timeIntervalSinceNow
            )
            return .notification(identifier)
        } catch {
            logger.error("Game reminder notification for \(productId) failed: \(error)")
            return nil
        }
    }

    func withdraw(_ delivery: GameReminderDelivery) async {
        switch delivery {
        case let .alarm(alarmId):
            if #available(iOS 26.1, *) {
                do {
                    try AlarmManager.shared.cancel(id: alarmId)
                } catch {
                    logger.debug("Game reminder alarm \(alarmId) was not cancelled: \(error)")
                }
            }
        case let .notification(identifier):
            notificationService.cancelScheduledNotifications(withIdentifiers: [identifier])
        }
    }

    @available(iOS 26.1, *)
    private func scheduleAlarm(id alarmId: UUID, productId: ProductId, fireDate: Date) async throws {
        let seconds = Int(GameReminderTiming.alarmLeadTime)
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(
                alert: .init(
                    title: .Notification.gameNotificationGameStartTitle(String(seconds)),
                    secondaryButton: .init(
                        text: .Notification.gameAlarmPlayGame,
                        textColor: .textAndIconsPrimaryDark,
                        systemImageName: "figure.walk.arrival"
                    ),
                    secondaryButtonBehavior: .custom
                )
            ),
            metadata: GameAlarmMetadata(timingSeconds: seconds),
            tintColor: Color.accentColor
        )

        let openIntent = GameReminderOpenIntent()
        openIntent.alarmID = alarmId.uuidString
        openIntent.productLink = GameReminderProductLink.url(for: productId)?.absoluteString

        _ = try await AlarmManager.shared.schedule(
            id: alarmId,
            configuration: AlarmManager.AlarmConfiguration(
                countdownDuration: nil,
                schedule: .fixed(fireDate),
                attributes: attributes,
                stopIntent: nil,
                secondaryIntent: openIntent,
                sound: .named("game_alarm.caf")
            )
        )
    }
}
