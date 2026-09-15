import Testing
import Foundation
@testable import polkadot_app

struct ChainHealthWindowTests {
    @Test("Empty window returns nil median")
    func emptyWindowMedian() {
        var window = ChainHealthWindow()

        #expect(window.median == nil)
    }

    @Test("Single sample median is that sample")
    func singleSampleMedian() {
        var window = ChainHealthWindow()
        window.record(0.75)

        #expect(window.median == 0.75)
    }

    @Test("Single outlier among nine good samples does not move median")
    func outlierDoesNotMoveMed() {
        var window = ChainHealthWindow()

        // Record nine good samples around 0.8
        for _ in 0 ..< 9 {
            window.record(0.8)
        }

        // Record one terrible outlier
        window.record(0)

        // Median should be 0.8 (not pulled down by the single 0)
        #expect(window.median == 0.8)
    }

    @Test("More than 10 samples keeps only last 10")
    func capacityTrimmed() {
        var window = ChainHealthWindow()

        // Record 15 samples: 0, 1, 2, ..., 14
        for i in 0 ..< 15 {
            window.record(Double(i) / 10)
        }

        // Should keep only last 10: 5/10 through 14/10
        let median = window.median

        // Sorted: 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4
        // Median at index 10/2 = 5 is 1.0
        #expect(median == 1.0)
    }
}
