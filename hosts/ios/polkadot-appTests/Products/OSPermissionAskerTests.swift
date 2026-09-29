import Foundation
import Products
import Testing
import UserNotifications
@testable import polkadot_app

@Suite("OS permission asker")
struct OSPermissionAskerTests {
    @Test(
        "The alarm status combines AlarmKit with notifications",
        arguments: [
            (OSPermissionStatus.notDetermined, NotificationAccessStatus.allowed, OSPermissionStatus.notDetermined),
            (.denied, .allowed, .allowed),
            (.denied, .notAllowed(denied: true), .denied),
            (.allowed, .notAllowed(denied: true), .allowed)
        ]
    )
    func alarmStatus(
        alarmKit: OSPermissionStatus,
        notifications: NotificationAccessStatus,
        expected: OSPermissionStatus
    ) async {
        let asker = OSPermissionAsker(
            notificationService: StubNotificationService(status: notifications),
            alarmKitStatus: { alarmKit }
        )

        #expect(await asker.checkPermission(for: .alarm) == expected)
    }
}

private struct StubNotificationService: UserNotificationServicing {
    let status: NotificationAccessStatus

    func notificationAccessStatus() async -> NotificationAccessStatus {
        status
    }

    func requestNotificationsAuthorization(completion _: ((Bool) -> Void)?) {}

    func scheduleNotification(
        withIdentifier _: String,
        content _: UNNotificationContent,
        after _: TimeInterval,
        completion _: ((Error?) -> Void)?
    ) {}

    func cancelScheduledNotifications(withIdentifiers _: [String]) {}

    func isNotificationScheduled(withIdentifier _: String, completion _: @escaping (Bool) -> Void) {}

    func deliveredNotifications() async -> [UNNotification] {
        []
    }

    func removeDeliveredNotifications(withIdentifiers _: [String]) {}

    func setBadge(_: Int) async {}
}
