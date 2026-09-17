import Foundation
import Testing
@testable import polkadot_app

/// Geometry of the single voucher bar: total length, and how it splits between the ceiling head
/// and the barber pole.
@Suite("Voucher status bar layout")
struct VoucherStatusLayoutTests {
    private let column: CGFloat = 200
    private let minimum = CoinageStatusMetrics.minimumBarWidth

    private func layout(max: UInt8, current: UInt8, width: CGFloat? = nil) -> VoucherStatusView.Layout {
        VoucherStatusView.layout(
            for: .init(maxFungibility: max, fungibility: current, isUnloadable: false),
            width: width ?? column
        )
    }

    // MARK: - Length

    @Test("Bar length tracks the current score")
    func lengthFollowsCurrentScore() {
        // 1 - 0.25
        #expect(layout(max: 25, current: 25).barWidth == 150)
    }

    /// The point of the linear scale: a barely started ring reads as barely started. Under the
    /// square root this drew at 90% of the column, which looked like real progress.
    @Test("A 1% ring draws a 99% bar")
    func lowScoreIsNearlyFull() {
        #expect(layout(max: 100, current: 1).barWidth == 198)
    }

    @Test("A longer bar means a less fungible voucher")
    func lowerScoreIsLonger() {
        #expect(layout(max: 100, current: 1).barWidth > layout(max: 100, current: 64).barWidth)
    }

    @Test("Bar never exceeds the column")
    func neverOverflows() {
        #expect(layout(max: 0, current: 0).barWidth == column)
    }

    @Test("Column narrower than the floor clamps to the column")
    func narrowColumn() {
        #expect(layout(max: 100, current: 100, width: 10).barWidth == 10)
    }

    // MARK: - The square floor

    @Test("A bar that would round away is widened to a square")
    func floorApplies() {
        #expect(layout(max: 100, current: 100).barWidth == minimum)
    }

    /// Head 1 - 0.96 = 0.04, total 1 - 0.92 = 0.08. Unfloored the bar would be 16pt of the 200pt
    /// column, so the floor widens it and both parts scale with it.
    @Test("Floor preserves the ratio between the two parts")
    func floorKeepsRatio() {
        let result = layout(max: 96, current: 92)

        #expect(result.barWidth == minimum)
        #expect(abs(result.solidShare - 0.5) < 0.000_01)
    }

    // MARK: - The split

    @Test("Both scores at full anonymity show only the head")
    func bothZeroShowsHead() {
        let result = layout(max: 100, current: 100)

        #expect(result.solidShare == 1)
        #expect(result.barWidth == minimum)
    }

    @Test("A ring that can reach full anonymity shows no head")
    func perfectCeilingHasNoHead() {
        #expect(layout(max: 100, current: 1).solidShare == 0)
    }

    @Test("A voucher already at its ceiling is all head")
    func atCeilingIsAllHead() {
        #expect(layout(max: 25, current: 25).solidShare == 1)
    }

    @Test("Head takes its share of the bar")
    func headShare() {
        // head 1 - 0.75 = 0.25, total 1 - 0.25 = 0.75
        let result = layout(max: 75, current: 25)

        #expect(abs(result.solidShare - 1.0 / 3) < 0.000_01)
    }

    /// The frozen ceiling and the live score are read at different times, so the pair can invert.
    @Test("An inverted pair clamps to all head instead of overrunning")
    func invertedPair() {
        let result = layout(max: 4, current: 81)

        #expect(result.solidShare == 1)
        #expect(result.barWidth == layout(max: 4, current: 4).barWidth)
    }

    // MARK: - Degenerate input

    @Test("Zero width yields no bar")
    func zeroWidth() {
        #expect(layout(max: 50, current: 20, width: 0).barWidth == 0)
    }
}
