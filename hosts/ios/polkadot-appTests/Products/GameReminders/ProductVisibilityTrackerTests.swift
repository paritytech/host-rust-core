import Foundation
import Testing

@testable import polkadot_app

@MainActor
@Suite("ProductVisibilityTracker")
struct ProductVisibilityTrackerTests {
    @Test("the mounted product is visible only while the app is active")
    func activeGate() {
        let tracker = ProductVisibilityTracker()
        tracker.setMountedProduct("jollity.dot")
        #expect(tracker.current == ProductVisibility(productId: "jollity.dot", isAppActive: true))

        tracker.setAppActive(false)
        #expect(tracker.current == ProductVisibility(productId: nil, isAppActive: false))

        tracker.setAppActive(true)
        #expect(tracker.current.productId == "jollity.dot")
    }

    @Test("changes yields the current value and each distinct change")
    func changesStream() async {
        let tracker = ProductVisibilityTracker()
        var iterator = tracker.changes().makeAsyncIterator()
        #expect(await iterator.next() == ProductVisibility(productId: nil, isAppActive: true))

        tracker.setMountedProduct("jollity.dot")
        tracker.setMountedProduct("jollity.dot")
        tracker.setMountedProduct(nil)

        #expect(await iterator.next()?.productId == "jollity.dot")
        #expect(await iterator.next()?.productId == nil)
    }
}
