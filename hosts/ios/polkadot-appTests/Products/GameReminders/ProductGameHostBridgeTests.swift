import Foundation
import Testing
import TrUAPIHost

@testable import polkadot_app

@Suite("ProductGameHostBridge")
struct ProductGameHostBridgeTests {
    @Test("scheduleReminder forwards the execution's product and the start in milliseconds")
    func forwardsSchedule() async throws {
        let reminders = MockGameReminderScheduling()
        let bridge = ProductGameHostBridge(productId: "jollity.dot", reminders: reminders)

        let (productId, startsAt) = await withCheckedContinuation { continuation in
            reminders.onSchedule = { continuation.resume(returning: ($0, $1)) }
            try? bridge.scheduleReminder(startsAt: 1_800_000_000_500)
        }

        #expect(productId == "jollity.dot")
        #expect(startsAt == Date(timeIntervalSince1970: 1_800_000_000.5))
    }

    @Test("cancelReminder forwards the execution's product")
    func forwardsCancel() async throws {
        let reminders = MockGameReminderScheduling()
        let bridge = ProductGameHostBridge(productId: "jollity.dot", reminders: reminders)

        let productId = await withCheckedContinuation { continuation in
            reminders.onCancel = { continuation.resume(returning: $0) }
            try? bridge.cancelReminder()
        }

        #expect(productId == "jollity.dot")
    }
}
