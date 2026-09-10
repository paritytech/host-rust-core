import Foundation
import SubstrateSdk

struct NotificationContentResult {
    let title: String
    let subtitle: String?
    let body: String
    let accountId: AccountId?
    let badgeCount: Int?

    init(
        title: String,
        subtitle: String? = nil,
        body: String,
        accountId: AccountId? = nil,
        badgeCount: Int? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.accountId = accountId
        self.badgeCount = badgeCount
    }
}

extension NotificationContentResult {
    func withBadgeCount(_ badgeCount: Int?) -> NotificationContentResult {
        .init(
            title: title,
            subtitle: subtitle,
            body: body,
            accountId: accountId,
            badgeCount: badgeCount
        )
    }

    static func createUnsupportedResult(badgeCount: Int? = nil) -> NotificationContentResult {
        .init(
            title: String(localized: .commonTitle),
            subtitle: nil,
            body: String(localized: .unsupportedMessage),
            badgeCount: badgeCount
        )
    }

    static func createBestAttemptResult() -> NotificationContentResult {
        .init(
            title: String(localized: .commonTitle),
            subtitle: nil,
            body: String(localized: .bestAttemptMessage)
        )
    }
}
