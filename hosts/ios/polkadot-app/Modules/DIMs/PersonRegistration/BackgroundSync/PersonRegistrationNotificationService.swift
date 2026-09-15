import Foundation
import UserNotifications

protocol PersonRegistrationNotificationServicing {
    func handleBackgroundSyncStateUpdate(_ state: PersonRegistrationSyncState)
    func handleBackgroundFetchScheduled(justEnteredBackground: Bool, isBackgroundSyncDone: Bool)
    func cancelPendingNotifications()
}

final class PersonRegistrationNotificationService {
    private let localNotificationService: UserNotificationServicing

    init(localNotificationService: UserNotificationServicing) {
        self.localNotificationService = localNotificationService
    }
}

// MARK: - PersonRegistrationNotificationServicing

extension PersonRegistrationNotificationService: PersonRegistrationNotificationServicing {
    func handleBackgroundSyncStateUpdate(_ state: PersonRegistrationSyncState) {
        let title: String?
        let body: String?

        switch state {
        case .personAdded:
            title = String(localized: .Notification.notificationPersonAddedTitle)
            body = String(localized: .Notification.notificationPersonAddedBody)
        case .aliasAssigned,
             .personRegistered:
            title = nil
            body = nil
        }

        guard let title, let body else {
            return
        }

        localNotificationService.scheduleNotification(
            withIdentifier: Identifiers.stateUpdated,
            content: makeContent(title: title, body: body),
            after: 0,
            completion: nil
        )
    }

    func handleBackgroundFetchScheduled(justEnteredBackground: Bool, isBackgroundSyncDone: Bool) {
        if isBackgroundSyncDone {
            cancelPendingNotifications()
            return
        }

        guard justEnteredBackground else {
            return
        }

        localNotificationService.scheduleNotification(
            withIdentifier: Identifiers.checkUpdates,
            content: makeContent(
                title: String(localized: .Notification.notificationPersonRegistrationCheckUpdateTitle),
                body: String(localized: .Notification.notificationPersonRegistrationCheckUpdateBody)
            ),
            after: TimeIntervals.checkUpdateNotification,
            completion: nil
        )
    }

    func cancelPendingNotifications() {
        localNotificationService.cancelScheduledNotifications(withIdentifiers: [
            Identifiers.checkUpdates,
            Identifiers.stateUpdated
        ])
    }
}

// MARK: - Private

private extension PersonRegistrationNotificationService {
    enum Identifiers {
        static let checkUpdates = "io.polkadotapp.personRegistration.checkUpdates"
        static let stateUpdated = "io.polkadotapp.personRegistration.stateUpdated"
    }

    enum TimeIntervals {
        static let checkUpdateNotification = TimeInterval(60 * 60 * 24)
    }

    func makeContent(title: String, body: String) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [PushNotificationKeys.chatExtensionId: PolkadotPeer.identifier]
        return content
    }
}
