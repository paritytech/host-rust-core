import Coinage
import DesignSystem
import PolkadotUI
import SwiftUI

/// A voucher's recycler status as one bar: a solid head for the anonymity its recycler can ever
/// reach, running straight into a barber pole covering the part still being earned.
///
/// Both lengths are inverted scores, so the bar reaches `1 − fungibility/100` of the column and
/// shrinks towards nothing as the recycler fills. Neither part has a floor of its own — a ring that
/// can reach full anonymity shows no head at all, and one already at its ceiling shows no pole.
struct VoucherStatusView: View {
    struct Model: Equatable {
        /// Frozen when the voucher entered its ring — the best the ring can still do.
        let maxFungibility: UInt8
        /// The ring's fungibility right now.
        let fungibility: UInt8
        /// Whether the current strategy would let this voucher be unloaded immediately.
        let isUnloadable: Bool
    }

    let model: Model
    var isAnimated: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let layout = Self.layout(for: model, width: geometry.size.width)

            DSProportionalBar(
                segments: Self.segments(for: model, layout: layout),
                height: CoinageStatusMetrics.barHeight,
                cornerStyle: .rounded(radius: CoinageStatusMetrics.solidBarCornerRadius),
                outlineColor: CoinageStatusMetrics.markFrame,
                outlineWidth: CoinageStatusMetrics.markFrameWidth,
                isAnimated: isAnimated
            )
            .frame(width: layout.barWidth)
            .frame(width: geometry.size.width, alignment: .leading)
        }
        .frame(height: CoinageStatusMetrics.barHeight)
    }
}

extension VoucherStatusView {
    struct Layout: Equatable {
        let barWidth: CGFloat
        /// Head's share of ``barWidth``, in 0...1. The pole takes the rest.
        let solidShare: CGFloat
    }

    /// Sizes the bar to `1 − current/100` of the column, with the head at `1 − max/100`.
    ///
    /// A bar that would round away is widened to a square floor rather than vanishing, and the two
    /// parts keep their ratio when that happens — the floor buys visibility, it must not
    /// misreport the split. When both scores are at full anonymity there is no ratio left to
    /// preserve, and the floor is all head.
    ///
    /// `max >= current` holds for any single reading, but the maximum is frozen at ring entry
    /// while the current score keeps updating — and the chain decrements its unloaded count on a
    /// failed dispatch — so a later reading can invert the pair. Clamping keeps the head from
    /// overrunning the bar.
    static func layout(for model: Model, width: CGFloat) -> Layout {
        guard width > 0 else { return Layout(barWidth: 0, solidShare: 1) }

        let solidFraction = CoinageStatusMetrics.fraction(forScore: model.maxFungibility)
        let totalFraction = max(
            CoinageStatusMetrics.fraction(forScore: model.fungibility),
            solidFraction
        )

        let barWidth = min(max(totalFraction * width, CoinageStatusMetrics.minimumBarWidth), width)

        return Layout(
            barWidth: barWidth,
            solidShare: totalFraction > 0 ? solidFraction / totalFraction : 1
        )
    }
}

private extension VoucherStatusView {
    static func segments(for model: Model, layout: Layout) -> [DSProportionalBar.Segment] {
        [
            .init(
                share: layout.solidShare,
                fill: .solid(model.isUnloadable ? Color.fgStaticWhite : Color.fgError)
            ),
            .init(
                share: 1 - layout.solidShare,
                fill: .stripes(color: Color.fgError, background: Color.fgStaticWhite)
            )
        ]
    }
}
