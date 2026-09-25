import Foundation
import Products

@testable import polkadot_app

final class MockGameReminderDelivery: GameReminderDelivering, @unchecked Sendable {
    private let lock = NSLock()
    private var _delivered: [(ProductId, Date)] = []
    private var _withdrawn: [GameReminderDelivery] = []
    private var _result: (ProductId) -> GameReminderDelivery? = { .notification("game:\($0)") }

    var delivered: [(ProductId, Date)] { lock.withLock { _delivered } }
    var withdrawn: [GameReminderDelivery] { lock.withLock { _withdrawn } }
    var result: (ProductId) -> GameReminderDelivery? {
        get { lock.withLock { _result } }
        set { lock.withLock { _result = newValue } }
    }

    func deliver(productId: ProductId, firingAt fireDate: Date) async -> GameReminderDelivery? {
        lock.withLock { _delivered.append((productId, fireDate)) }
        return lock.withLock { _result }(productId)
    }

    func withdraw(_ delivery: GameReminderDelivery) async {
        lock.withLock { _withdrawn.append(delivery) }
    }
}
