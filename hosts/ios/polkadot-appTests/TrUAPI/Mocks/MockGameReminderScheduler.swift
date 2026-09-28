import Foundation
import Products
@testable import polkadot_app

@MainActor
final class MockGameReminderScheduler: ProductGameReminderScheduling {
    func schedule(productId _: ProductId, startsAt _: Date) {}

    func cancel(productId _: ProductId) {}
}
