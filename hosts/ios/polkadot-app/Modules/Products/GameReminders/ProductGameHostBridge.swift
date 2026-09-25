import Foundation
import Products
import TrUAPIHost

/// The TrUAPI game-reminder surface for one product execution. It hands each call to the app-wide
/// ``GameReminderCenter`` and returns at once, because the core calls it on a dispatch pool shared by every
/// product execution.
final class ProductGameHostBridge: GameHostBridge, @unchecked Sendable {
    private let productId: ProductId
    private let reminders: GameReminderScheduling

    init(productId: ProductId, reminders: GameReminderScheduling) {
        self.productId = productId
        self.reminders = reminders
    }

    func scheduleReminder(startsAt: UInt64) throws {
        let date = Date(timeIntervalSince1970: TimeInterval(startsAt) / 1000)
        Task { [reminders, productId] in
            await reminders.schedule(productId: productId, startsAt: date)
        }
    }

    func cancelReminder() throws {
        Task { [reminders, productId] in
            await reminders.cancel(productId: productId)
        }
    }
}
