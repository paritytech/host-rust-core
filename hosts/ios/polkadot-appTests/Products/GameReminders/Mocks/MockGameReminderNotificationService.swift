import Foundation
import UserNotifications

@testable import polkadot_app

final class MockGameReminderNotificationService: UserNotificationServicing, @unchecked Sendable {
    let status: NotificationAccessStatus
    private(set) var scheduledIdentifiers: [String] = []
    private(set) var scheduledAfter: [TimeInterval] = []
    private(set) var scheduledContents: [UNNotificationContent] = []
    private(set) var cancelledIdentifiers: [String] = []

    init(status: NotificationAccessStatus) {
        self.status = status
    }

    func notificationAccessStatus() async -> NotificationAccessStatus { status }
    func requestNotificationsAuthorization(completion: ((Bool) -> Void)?) { completion?(status == .allowed) }
    func scheduleNotification(
        withIdentifier identifier: String,
        content: UNNotificationContent,
        after timeInterval: TimeInterval,
        completion: ((Error?) -> Void)?
    ) {
        scheduledIdentifiers.append(identifier)
        scheduledAfter.append(timeInterval)
        scheduledContents.append(content)
        completion?(nil)
    }
    func cancelScheduledNotifications(withIdentifiers identifiers: [String]) {
        cancelledIdentifiers.append(contentsOf: identifiers)
    }
    func isNotificationScheduled(withIdentifier _: String, completion: @escaping (Bool) -> Void) { completion(false) }
    func deliveredNotifications() async -> [UNNotification] { [] }
    func removeDeliveredNotifications(withIdentifiers _: [String]) {}
    func setBadge(_: Int) async {}
}
