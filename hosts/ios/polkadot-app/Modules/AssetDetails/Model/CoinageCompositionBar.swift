import DesignSystem
import PolkadotUI
import SwiftUI

/// Value-weighted picture of the three balance figures shown above it: available now, gaining
/// privacy, and pending.
///
/// Each section is the same bucket as the row above it, so the bar is a legend-free depiction of
/// those numbers rather than a second, differently-cut summary. Coins and vouchers land in
/// whichever bucket the strategy puts them in — a voucher ready to unload counts as available,
/// exactly as the figure above does.
///
/// Only the bucket-to-segment mapping lives here; the drawing is ``DSProportionalBar``.
struct CoinageCompositionBar: View {
    struct Model: Equatable {
        let availableNowShare: Double
        let gainingPrivacyShare: Double
        let pendingShare: Double

        static let empty = Model(
            availableNowShare: 0,
            gainingPrivacyShare: 0,
            pendingShare: 0
        )

        var isEmpty: Bool {
            availableNowShare + gainingPrivacyShare + pendingShare <= 0
        }
    }

    let model: Model

    var body: some View {
        DSProportionalBar(
            segments: Self.segments(for: model),
            height: CoinageStatusMetrics.summaryBarHeight,
            outlineColor: CoinageStatusMetrics.markFrame,
            outlineWidth: CoinageStatusMetrics.markFrameWidth
        )
    }
}

private extension CoinageCompositionBar {
    static func segments(for model: Model) -> [DSProportionalBar.Segment] {
        [
            .init(share: model.availableNowShare, fill: .solid(Color.fgStaticWhite)),
            .init(
                share: model.gainingPrivacyShare,
                fill: .stripes(color: Color.fgError, background: Color.fgStaticWhite)
            ),
            .init(share: model.pendingShare, fill: .solid(Color.fgError))
        ]
    }
}
