import Foundation
import Testing
import UserNotifications

@testable import polkadot_app

@Suite("GameReminderDelivery")
struct GameReminderDeliveryTests {
    @Test("the product link is the product's universal link")
    func productLink() throws {
        let url = try #require(GameReminderProductLink.url(for: "jollity.dot"))
        #expect(url.host?.hasPrefix("jollity.") == true)
        #expect(url.scheme == AppConfig.ProductUniversalLink.scheme)
    }

    @Test("the notification routes to the product and rings the game tone")
    func notificationContent() throws {
        let content = GameReminderNotificationContent.make(productId: "jollity.dot")
        #expect(content.userInfo[PushNotificationKeys.pushSource] as? Int == PushNotificationSource.products.rawValue)
        let deeplink = try #require(content.userInfo[PushNotificationKeys.deeplink] as? String)
        #expect(deeplink == GameReminderProductLink.url(for: "jollity.dot")?.absoluteString)
        #expect(!content.title.isEmpty)
        #expect(!content.body.isEmpty)
    }

    @Test("without alarm authorization a notification is scheduled when notifications are allowed")
    func notificationFallback() async throws {
        let service = MockGameReminderNotificationService(status: .allowed)
        let delivery = SystemGameReminderDelivery(notificationService: service, alarmsAvailable: { false })
        let fire = Date().addingTimeInterval(600)

        let result = await delivery.deliver(productId: "jollity.dot", firingAt: fire)

        #expect(result == .notification("game:jollity.dot"))
        #expect(service.scheduledIdentifiers == ["game:jollity.dot"])
        let interval = try #require(service.scheduledAfter.first)
        #expect(abs(interval - 600) < 5)
        let content = try #require(service.scheduledContents.first)
        #expect(content.title == String(
            localized: .Notification.gameNotificationGameStartTitle(String(Int(GameReminderTiming.alarmLeadTime)))
        ))
    }

    @Test("a fire date that has already passed schedules nothing")
    func pastFireDate() async {
        let service = MockGameReminderNotificationService(status: .allowed)
        let delivery = SystemGameReminderDelivery(notificationService: service, alarmsAvailable: { false })

        let result = await delivery.deliver(productId: "jollity.dot", firingAt: Date().addingTimeInterval(-1))

        #expect(result == nil)
        #expect(service.scheduledIdentifiers.isEmpty)
    }

    @Test("with neither alarms nor notifications nothing is scheduled")
    func noDelivery() async {
        let service = MockGameReminderNotificationService(status: .notAllowed(denied: true))
        let delivery = SystemGameReminderDelivery(notificationService: service, alarmsAvailable: { false })

        let result = await delivery.deliver(productId: "jollity.dot", firingAt: Date().addingTimeInterval(600))

        #expect(result == nil)
        #expect(service.scheduledIdentifiers.isEmpty)
    }

    @Test("withdrawing a notification cancels its identifier")
    func withdrawNotification() async {
        let service = MockGameReminderNotificationService(status: .allowed)
        let delivery = SystemGameReminderDelivery(notificationService: service, alarmsAvailable: { false })

        await delivery.withdraw(.notification("game:jollity.dot"))

        #expect(service.cancelledIdentifiers == ["game:jollity.dot"])
    }
}
