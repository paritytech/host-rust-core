import Foundation
import UserNotifications

protocol DIM1NotificationServicing {
    func handleBackgroundSyncStateUpdate(_ state: DIM1BackgroundSyncState)
    func handleBackgroundFetchScheduled(justEnteredBackground: Bool, isBackgroundSyncDone: Bool)
    func cancelPendingNotifications()
}

final class DIM1NotificationService {
    private let localNotificationService: UserNotificationServicing

    init(localNotificationService: UserNotificationServicing) {
        self.localNotificationService = localNotificationService
    }
}

// MARK: - DIM1NotificationServicing

extension DIM1NotificationService: DIM1NotificationServicing {
    func handleBackgroundSyncStateUpdate(_ state: DIM1BackgroundSyncState) {
        let title: String?
        let body: String?

        switch state {
        case .photoReviewed:
            title = String(localized: .Notification.notificationDim1StateChangedTitle)
            body = String(localized: .Notification.notificationDim1StateChangedPhotoReviewedBody)
        case .videoReviewed:
            title = String(localized: .Notification.notificationDim1StateChangedTitle)
            body = String(localized: .Notification.notificationDim1StateChangedVideoReviewedBody)
        case .none,
             .photoSubmission,
             .photoInReview,
             .videoSubmission,
             .videoInReview:
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
                title: String(localized: .Notification.notificationDim1CheckUpdateTitle),
                body: String(localized: .Notification.notificationDim1CheckUpdateBody)
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

private extension DIM1NotificationService {
    enum Identifiers {
        static let checkUpdates = "io.polkadotapp.dim1.checkUpdates"
        static let stateUpdated = "io.polkadotapp.dim1.stateUpdated"
    }

    enum TimeIntervals {
        static let checkUpdateNotification = TimeInterval(60 * 60 * 24)
    }

    func makeContent(title: String, body: String) -> UNNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [PushNotificationKeys.chatExtensionId: DIM1ChatExtension.identifier]
        return content
    }
}
