import Testing
import SwiftUI
@testable import PolkadotUI

struct DSProportionalBarTests {
    private func segments(_ shares: [Double]) -> [DSProportionalBar.Segment] {
        shares.map { .init(share: $0, fill: .solid(.clear)) }
    }

    // MARK: - Filling the bar

    @Test("Widths sum to the full width")
    func widthsFillBar() {
        let widths = DSProportionalBar.widths(for: segments([0.5, 0.2, 0.3]), totalWidth: 200)

        #expect(widths.reduce(0, +) == 200)
    }

    @Test("Shares are laid out in order")
    func widthsFollowShares() {
        let widths = DSProportionalBar.widths(for: segments([0.5, 0.2, 0.3]), totalWidth: 200)

        #expect(widths == [100, 40, 60])
    }

    /// Callers computing shares by integer division leave a shortfall; the last segment has to
    /// absorb it or a gap appears at the trailing edge.
    @Test("Last segment absorbs a shortfall in the shares")
    func lastSegmentAbsorbsShortfall() {
        let widths = DSProportionalBar.widths(for: segments([0.3, 0.3, 0.3]), totalWidth: 100)

        #expect(widths == [30, 30, 40])
    }

    @Test("Widths still fill a bar whose width rounds unevenly")
    func widthsFillUnevenBar() {
        let widths = DSProportionalBar.widths(for: segments([1 / 3, 1 / 3, 1 / 3]), totalWidth: 101)

        #expect(widths.reduce(0, +) == 101)
        #expect(widths.allSatisfy { $0 > 0 })
    }

    @Test("Rounding never produces a negative width")
    func noNegativeWidths() {
        let widths = DSProportionalBar.widths(for: segments([0.9, 0.9]), totalWidth: 100)

        #expect(widths.allSatisfy { $0 >= 0 })
    }

    // MARK: - Degenerate input

    @Test("All-zero shares collapse every segment")
    func emptyShares() {
        let widths = DSProportionalBar.widths(for: segments([0, 0, 0]), totalWidth: 200)

        #expect(widths == [0, 0, 0])
    }

    @Test("Zero width collapses every segment")
    func zeroWidth() {
        let widths = DSProportionalBar.widths(for: segments([0.5, 0.5]), totalWidth: 0)

        #expect(widths == [0, 0])
    }

    @Test("No segments yields no widths")
    func noSegments() {
        #expect(DSProportionalBar.widths(for: [], totalWidth: 200).isEmpty)
    }

    @Test("A single segment takes the whole bar")
    func singleSegment() {
        #expect(DSProportionalBar.widths(for: segments([1]), totalWidth: 200) == [200])
    }
}
