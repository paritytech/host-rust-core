import DesignSystem
import PolkadotUI
import SwiftUI

/// Swatch keying one summary figure to its section of the bar above.
///
/// The gaining-privacy swatch is the same ``DSBarberPole`` the bar and the voucher rows use, so
/// there is one striped thing in the screen rather than three that merely resemble each other.
struct CoinageLegendSwatch: View {
    enum Kind {
        case availableNow
        case gainingPrivacy
        case unavailable
    }

    let kind: Kind

    var body: some View {
        shape
            .frame(
                width: CoinageStatusMetrics.legendSwatchSize,
                height: CoinageStatusMetrics.legendSwatchSize
            )
            .clipShape(
                RoundedRectangle(cornerRadius: CoinageStatusMetrics.legendSwatchCornerRadius)
            )
            // The white swatch would vanish into a light theme's summary box without it.
            .overlay(
                RoundedRectangle(cornerRadius: CoinageStatusMetrics.legendSwatchCornerRadius)
                    .stroke(
                        CoinageStatusMetrics.markFrame,
                        lineWidth: CoinageStatusMetrics.markFrameWidth
                    )
            )
    }

    @ViewBuilder
    private var shape: some View {
        switch kind {
        case .availableNow: Color.fgStaticWhite
        case .gainingPrivacy: DSBarberPole()
        case .unavailable: Color.fgError
        }
    }
}

/// Collapsed key to the depictions in the details list.
///
/// Every illustration is the real drawing code at a fixed width, not a facsimile, so the key
/// cannot describe a mark the list has stopped drawing.
struct CoinageExplanationView: View {
    /// Owned by the caller: the state has to outlive the holdings updating underneath it.
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 12) {
            header

            if isExpanded {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Self.entries) { entry in
                        row(entry)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bgSurfaceNested, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text(String(localized: .coinageHowToRead))
                    .textStyle(.body14Regular())
                Spacer()
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption)
            }
            .foregroundStyle(Color.fgSecondary)
            // The row is mostly the Spacer between label and chevron, and a Spacer draws
            // nothing, so without this the middle of the row is not hit-testable.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ entry: Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            entry.illustration
                .frame(width: Self.illustrationWidth, alignment: .leading)

            Text(entry.text)
                .textStyle(.caption13Regular())
                .foregroundStyle(Color.fgSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension CoinageExplanationView {
    static let illustrationWidth: CGFloat = 56

    struct Entry: Identifiable {
        let id: String
        let text: String
        let illustration: AnyView
    }

    /// Deliberately plain: what the mark means, and which direction is worse. The exact scale is
    /// not something the reader can act on, so it is left out.
    static var entries: [Entry] {
        [
            Entry(
                id: "hops",
                text: String(localized: .coinageKeyHops),
                illustration: AnyView(
                    HStack(spacing: CoinageStatusMetrics.itemSpacing) {
                        CoinStatusView.CircleIllustration(dots: 0)
                        CoinStatusView.CircleIllustration(dots: 3)
                    }
                )
            ),
            Entry(
                id: "unknown",
                text: String(localized: .coinageKeyUnknown),
                illustration: AnyView(CoinStatusView.UnknownIllustration())
            ),
            Entry(
                id: "solid",
                text: String(localized: .coinageKeySolid),
                illustration: AnyView(
                    CoinStatusView(
                        model: .init(hopDots: [], fungibility: 25, isSpendable: true)
                    )
                )
            ),
            Entry(
                id: "voucher",
                text: String(localized: .coinageKeyVoucher),
                illustration: AnyView(
                    VoucherStatusView(
                        model: .init(maxFungibility: 55, fungibility: 15, isUnloadable: false)
                    )
                )
            )
        ]
    }
}
