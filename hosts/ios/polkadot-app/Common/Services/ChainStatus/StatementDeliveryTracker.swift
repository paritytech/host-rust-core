import Foundation
import AsyncExtensions
import StatementStore
import PolkadotUI

enum StatementDeliveryState: Hashable {
    case noSubscriptions
    case active
    case failed
}

extension StatementDeliveryState {
    var connectionState: ChainConnectionState {
        switch self {
        case .noSubscriptions:
            .connecting
        case .active:
            .connected
        case .failed:
            .offline
        }
    }
}

protocol StatementDeliveryTracking: AnyObject, Sendable {
    func stateStream() -> AnyAsyncSequence<StatementDeliveryState>
    func report(_ state: StatementDeliveryState)
}

final class StatementDeliveryTracker: StatementDeliveryTracking {
    private let subject = AsyncCurrentValueSubject<StatementDeliveryState>(.noSubscriptions)

    func stateStream() -> AnyAsyncSequence<StatementDeliveryState> {
        subject.eraseToAnyAsyncSequence()
    }

    func report(_ state: StatementDeliveryState) {
        subject.send(state)
    }
}
