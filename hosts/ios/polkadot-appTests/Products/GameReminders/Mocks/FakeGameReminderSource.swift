import Foundation
import Products

@testable import polkadot_app

final class FakeGameReminderSource: GameReminderObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var _marked: [ProductId] = []
    private var _left: [ProductId] = []
    private var _suppressed: [ProductId] = []
    private var _terminated = false

    var marked: [ProductId] { lock.withLock { _marked } }
    var left: [ProductId] { lock.withLock { _left } }
    var suppressed: [ProductId] { lock.withLock { _suppressed } }
    /// Set once a consumer's `changes()` stream is torn down, e.g. by cancelling the task iterating it.
    var terminated: Bool { lock.withLock { _terminated } }

    /// Never finishes on its own, so a consumer only stops iterating it by cancelling its own task.
    func changes() async -> AsyncStream<[GameReminder]> {
        AsyncStream { [self] continuation in
            continuation.onTermination = { [self] _ in
                lock.withLock { _terminated = true }
            }
        }
    }

    func markOpened(productId: ProductId) async { lock.withLock { _marked.append(productId) } }
    func productLeft(productId: ProductId) async { lock.withLock { _left.append(productId) } }
    func suppressAlarm(productId: ProductId) async { lock.withLock { _suppressed.append(productId) } }
}
