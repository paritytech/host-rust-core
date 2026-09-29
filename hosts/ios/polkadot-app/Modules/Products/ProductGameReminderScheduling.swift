import Foundation
import Products

enum ProductGameScheduleOutcome: Equatable {
    case scheduled
    /// Another product holds the reminder.
    case busy
}

/// Schedules and cancels a product's next-game reminder.
/// Temporary: will be replaced by generic reminder and pill APIs.
@MainActor
protocol ProductGameReminderScheduling: AnyObject {
    /// `ringAlarm` false delivers an ordinary notification, not an alarm.
    func schedule(
        productId: ProductId,
        startsAt: Date,
        ringAlarm: Bool,
        addCalendarEvent: Bool
    ) async -> ProductGameScheduleOutcome

    func cancel(productId: ProductId)
}
