import SwiftUI
import DesignSystem

/// Per-chain readout of every monitored connection. It repeats the top strip's ring at a larger
/// size so the two read as the same mark, and names the health grade and block age beside it.
public struct ConnectionStatusPanelView: View, Hashable {
    public let rows: [ChainConnectionStatusViewModel]

    public init(rows: [ChainConnectionStatusViewModel]) {
        self.rows = rows
    }

    public var body: some View {
        // `ChainStatusProvider` drops identical row sets, so a stalled chain stops emitting
        // entirely. Block age therefore ticks on a view-local timeline rather than on emissions,
        // otherwise it would freeze exactly when the panel is opened to diagnose the stall.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: DSSpacings.mediumIncreased) {
                Text(.Common.connectionStatusPanelTitle)
                    .typography(.titleLarge)
                    .foregroundStyle(Color.fgPrimary)
                    .lineLimit(1)
                    .padding(.bottom, DSSpacings.small)

                ForEach(rows) { row in
                    rowView(row, now: context.date)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DSSpacings.mediumIncreased)
        }
    }
}

private extension ConnectionStatusPanelView {
    static let placeholder = "—"

    /// Block age is right-anchored at this width so the "Block:" label beside it stays put when the
    /// value gains a digit; `codeSmall` provides the monospaced font for steady alignment between those steps.
    static let blockAgeMinWidth: CGFloat = 16

    static let blockAgeFormatter = DateComponentsFormatter.secondsMinutesAbbreviated

    func rowView(_ row: ChainConnectionStatusViewModel, now: Date) -> some View {
        HStack(spacing: DSSpacings.extraMedium) {
            ChainStatusRingView(viewModel: row, diameter: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DSSpacings.extraTiny) {
                Text(verbatim: row.title)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.fgPrimary)
                    .lineLimit(1)

                Text(verbatim: subtitle(row))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.fgSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(.Common.connectionStatusBlockLabel)
                .typography(.bodySmall)
                .foregroundStyle(Color.fgSecondary)
                .lineLimit(1)

            Text(verbatim: blockAgeText(row.lastBlockDate, now: now))
                .typography(.codeSmall)
                .foregroundStyle(Color.fgPrimary)
                .lineLimit(1)
                .frame(minWidth: Self.blockAgeMinWidth, alignment: .trailing)
        }
    }

    func subtitle(_ row: ChainConnectionStatusViewModel) -> String {
        guard row.state == .connected else {
            return row.stateTitle
        }

        let grade =
            switch row.healthGrade {
            case .excellent: String(localized: .Common.connectionStatusHealthExcellent)
            case .good: String(localized: .Common.connectionStatusHealthGood)
            case .fair: String(localized: .Common.connectionStatusHealthFair)
            case .poor: String(localized: .Common.connectionStatusHealthPoor)
            }

        return String(localized: .Common.connectionStatusSpeedValue(grade))
    }

    /// The result is displayed with `lineLimit(1)` because the panel measures its content only
    /// when a configuration is pushed, so wrapped text on a timeline tick would grow content
    /// without resizing the panel.
    func blockAgeText(_ lastBlockDate: Date?, now: Date) -> String {
        guard
            let lastBlockDate,
            let age = Self.blockAgeFormatter.string(
                from: max(0, now.timeIntervalSince(lastBlockDate))
            )
        else {
            return Self.placeholder
        }

        return age
    }
}
