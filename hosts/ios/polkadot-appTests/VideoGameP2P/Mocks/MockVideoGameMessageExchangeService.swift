@testable import polkadot_app
import Foundation
import MessageExchangeKit

final class MockVideoGameMessageExchangeService: MessageExchangeServicing {
    typealias Message = OpaqueVideoGameSignalingEnvelope

    private let lock = NSLock()
    private var messages: [OpaqueVideoGameSignalingEnvelope] = []
    private var messageBatches: [[OpaqueVideoGameSignalingEnvelope]] = []

    var queuedMessages: [OpaqueVideoGameSignalingEnvelope] {
        lock.withLock { messages }
    }

    var queuedMessageBatches: [[OpaqueVideoGameSignalingEnvelope]] {
        lock.withLock { messageBatches }
    }

    func updateSessions(_: Set<MessageExchange.SessionRequest>) {}

    func addMessagesToQueue(
        _ messages: [OpaqueVideoGameSignalingEnvelope],
        for _: MessageExchange.Peer
    ) {
        lock.withLock {
            self.messages.append(contentsOf: messages)
            self.messageBatches.append(messages)
        }
    }
}
