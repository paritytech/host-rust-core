import Foundation
import EventCenter

@testable import polkadot_app

final class MockEventCenter: EventCenterProtocol {
    var onEvent: ((EventProtocol) -> Void)?

    private var observers: [WeakEventVisitor] = []

    func notify(with event: EventProtocol) {
        onEvent?(event)

        observers.removeAll { $0.observer == nil }

        for observer in observers.compactMap(\.observer) {
            event.accept(visitor: observer)
        }
    }

    func add(observer: EventVisitorProtocol, dispatchIn _: DispatchQueue?) {
        observers.append(WeakEventVisitor(observer: observer))
    }

    func remove(observer: EventVisitorProtocol) {
        observers.removeAll { $0.observer === observer }
    }
}

private final class WeakEventVisitor {
    weak var observer: EventVisitorProtocol?

    init(observer: EventVisitorProtocol) {
        self.observer = observer
    }
}
