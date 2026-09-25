import Foundation
import Products

@testable import polkadot_app

final class MockGameReminderScheduling: GameReminderScheduling, @unchecked Sendable {
    var onSchedule: ((ProductId, Date) -> Void)?
    var onCancel: ((ProductId) -> Void)?

    func schedule(productId: ProductId, startsAt: Date) async { onSchedule?(productId, startsAt) }
    func cancel(productId: ProductId) async { onCancel?(productId) }
}
