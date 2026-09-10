import Foundation
import EventCenter

@testable import polkadot_app

final class MockEventCenter: EventCenterProtocol {
    var onEvent: ((EventProtocol) -> Void)?

    func notify(with event: EventProtocol) {
        onEvent?(event)
    }

    func add(observer _: EventVisitorProtocol, dispatchIn _: DispatchQueue?) {}
    func remove(observer _: EventVisitorProtocol) {}
}
