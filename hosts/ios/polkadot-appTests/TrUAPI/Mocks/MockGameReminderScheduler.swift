import Foundation
import Products
@testable import polkadot_app

@MainActor
final class MockGameReminderScheduler: ProductGameReminderScheduling {
    struct Call: Equatable {
        let productId: ProductId
        let startsAt: Date
        let ringAlarm: Bool
        let addCalendarEvent: Bool
    }

    var outcome: ProductGameScheduleOutcome = .scheduled
    private(set) var scheduled: [Call] = []

    func schedule(
        productId: ProductId,
        startsAt: Date,
        ringAlarm: Bool,
        addCalendarEvent: Bool
    ) async -> ProductGameScheduleOutcome {
        scheduled.append(
            Call(productId: productId, startsAt: startsAt, ringAlarm: ringAlarm, addCalendarEvent: addCalendarEvent)
        )
        return outcome
    }

    func cancel(productId _: ProductId) {}
}
