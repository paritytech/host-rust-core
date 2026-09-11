import Foundation
import ChainRegistry
import EventCenter

struct BalanceSyncState: EventProtocol {
    func accept(visitor: EventVisitorProtocol) {
        (visitor as? AppEventVisiting)?.processBalanceSyncState(event: self)
    }
}
