import Foundation
import Products

/// Schedules and cancels a product's next-game reminder.
@MainActor
protocol ProductGameReminderScheduling: AnyObject {
    /// Replaces the reminder the product already holds. `ringAlarm` false delivers an ordinary
    /// notification, not an alarm.
    func schedule(
        productId: ProductId,
        startsAt: Date,
        ringAlarm: Bool,
        addCalendarEvent: Bool
    ) async

    func cancel(productId: ProductId)
}
