import SwiftUI
import ExternalAccessibility
import PolkadotUI
import DesignSystem

struct AssetDetailsView: View {
    @State var viewModel: AssetDetailsViewModelProtocol
    var isExpanded: Bool = false
    var onCardTapped: () -> Void
    var overscroll: CGFloat = 0
    var onCollapse: (() -> Void)?

    init(
        viewModel: AssetDetailsViewModelProtocol = AssetDetailsViewModel(),
        isExpanded: Bool = false,
        onCardTapped: @escaping () -> Void,
        overscroll: CGFloat = 0,
        onCollapse: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.isExpanded = isExpanded
        self.onCardTapped = onCardTapped
        self.overscroll = overscroll
        self.onCollapse = onCollapse
    }

    var body: some View {
        DSExpandableCardLayout(
            isExpanded: isExpanded,
            overscroll: overscroll,
            onCollapse: onCollapse,
            card: { headerCard },
            details: { expandedBody }
        )
    }

    @ViewBuilder
    private var headerCard: some View {
        if let balanceCardModel = viewModel.balanceCardModel {
            balanceCard(balanceCardModel)
                .onTapGesture { onCardTapped() }
        }
    }

    @ViewBuilder
    private var expandedBody: some View {
        VStack(spacing: 16) {
            if viewModel.showsAccountBackupPending {
                AccountBackupPendingView()
            }
            if viewModel.showsBackupNotification {
                backupCard()
            } else {
                actions()
            }
            if let breakdown = viewModel.coinageBreakdown,
               viewModel.balanceCardModel != nil {
                CoinageBalanceBreakdownView(breakdown: breakdown)
            }

            #if TESTNET_FEATURE
                HStack {
                    VStack { Divider().background(Color.fgPrimary) }
                    Text(verbatim: "Debug features")
                        .typography(.labelMedium)
                        .foregroundStyle(Color.fgPrimary)
                    VStack { Divider().background(Color.fgPrimary) }
                }

                testnetTopUpButton()
            #endif
        }
    }

    private func balanceCard(
        _ balanceCardModel: AssetDetailsBalanceCard.ViewModel
    ) -> some View {
        AssetDetailsBalanceCard(
            viewModel: balanceCardModel,
            isUpdating: viewModel.isUpdating,
            isExpanded: isExpanded
        )
    }

    private func backupCard() -> some View {
        WalletBackupNotificationCard(
            isUpdating: viewModel.isUpdating,
            onSync: viewModel.onBackupSync,
            onCancel: viewModel.onBackupCancel,
            onWhyUpdate: viewModel.onBackupWhyUpdate
        )
    }

    private func actions() -> some View {
        HStack(spacing: 12) {
            DSButton(.actionSendCash, leadingIcon: .iconArrowUp16, expands: true) {
                viewModel.onSendMoney?()
            }
            .accessibilityId(AccessibilityID.Wallet.sendPaymentButton)

            circleButton(.iconArrowUpRight24, isLoading: viewModel.isWithdrawInProgress) {
                viewModel.onWithdraw?()
            }
            .accessibilityId(AccessibilityID.Wallet.withdrawButton)

            circleButton(.add24, isLoading: viewModel.isTopUpInProgress) {
                viewModel.onTopUp?()
            }
            .accessibilityId(AccessibilityID.Wallet.addFundsButton)
        }
    }

    private func circleButton(
        _ icon: ImageResource,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.fgPrimaryInverted)
                } else {
                    Image(icon)
                        .renderingMode(.template)
                }
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.fgPrimaryInverted)
            .background(.bgActionPrimary, in: Circle())
        }
        .disabled(isLoading)
    }

    #if TESTNET_FEATURE
        private func testnetTopUpButton() -> some View {
            Button {
                viewModel.onTestnetTopUp?()
            } label: {
                Group {
                    if viewModel.isTestnetTopUpInProgress {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.fgPrimaryInverted)
                    } else {
                        Text(verbatim: "Faucet Top Up")
                            .textStyle(.body14SemiBold())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(Color.fgPrimaryInverted)
                .background(.bgActionPrimary, in: RoundedRectangle(cornerRadius: 12))
            }
            .disabled(viewModel.isTestnetTopUpInProgress)
        }
    #endif
}

/// Funding progress banner. Pinned by the wallet host while the asset card is expanded.
struct AssetDetailsFundingBar: View {
    @Bindable var viewModel: AssetDetailsViewModel

    var body: some View {
        if !viewModel.fundingStates.isEmpty {
            AssetFundingStatusView(
                states: $viewModel.fundingStates,
                isExpanded: $viewModel.isFundingExpanded,
                configuration: .fundingDigitalDollarConfiguration(
                    onCompletedAction: viewModel.onFundingCompleted,
                    onFailedAction: viewModel.onFundingFailed
                )
            )
            .frame(maxWidth: .infinity)
        }
    }
}

private struct CoinageBalanceBreakdownView: View {
    let breakdown: CoinageBalanceBreakdownViewModel

    @State private var showDetails = false
    @State private var showExplanation = false

    var body: some View {
        VStack(spacing: 12) {
            Text(String(localized: .coinageSummaryTitle))
                .textStyle(.title16SemiBold())
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityId(AccessibilityID.Wallet.coinageHeader)

            totalHeadline

            CoinageCompositionBar(model: breakdown.composition)
                .padding(.vertical, 2)

            summaryLegend

            Button {
                withAnimation { showDetails.toggle() }
            } label: {
                HStack {
                    Text(String(localized: showDetails ? .coinageHideDetails : .coinageShowDetails))
                        .textStyle(.body14SemiBold())
                    Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .foregroundStyle(.fgPrimary)
            }

            if showDetails {
                CoinageDetailsView(breakdown: breakdown)
                CoinageExplanationView(isExpanded: $showExplanation)
            }
        }
        .padding(16)
        .background(.bgSurfaceContainer, in: RoundedRectangle(cornerRadius: 24))
    }

    private var totalHeadline: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: .coinageTotalBalance))
                .textStyle(.caption12Regular())
                .foregroundStyle(Color.fgSecondary)
                .accessibilityId(AccessibilityID.Wallet.coinageTotalBalanceLabel)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(breakdown.totalBalance)
                    .textStyle(.title32SemiBold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityId(AccessibilityID.Wallet.coinageTotalBalanceValue)

                Text(breakdown.symbol)
                    .textStyle(.caption12Regular())
                    .foregroundStyle(Color.fgSecondary)
            }
            .foregroundStyle(Color.fgPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The three figures partition the total and are the three sections of the bar above, in the
    /// same order, each keyed to its section by a swatch.
    ///
    /// A grid rather than three stacked columns: a label long enough to wrap would otherwise push
    /// its own value down and leave the three figures on different lines.
    private var summaryLegend: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow {
                ForEach(legendEntries) { entry in
                    HStack(spacing: 6) {
                        CoinageLegendSwatch(kind: entry.kind)

                        Text(entry.title)
                            .textStyle(.caption12Regular())
                            .foregroundStyle(Color.fgSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityId(entry.labelAccessibilityId)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .gridCellAnchor(.topLeading)

            GridRow {
                ForEach(legendEntries) { entry in
                    Text(entry.value)
                        .textStyle(.body14SemiBold())
                        .foregroundStyle(Color.fgPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityId(entry.valueAccessibilityId)
                }
            }
        }
    }

    private var legendEntries: [LegendEntry] {
        [
            LegendEntry(
                kind: .availableNow,
                title: String(localized: .coinageSpendable),
                value: breakdown.availableNowBalance,
                labelAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceLabel,
                valueAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceValue
            ),
            // No accessibility id yet: the registry lives in another repo.
            LegendEntry(
                kind: .gainingPrivacy,
                title: String(localized: .coinageLoading),
                value: breakdown.gainingPrivacyBalance
            ),
            LegendEntry(
                kind: .unavailable,
                title: String(localized: .coinageUnavailable),
                value: breakdown.pendingBalance,
                labelAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceLabel,
                valueAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceValue
            )
        ]
    }
}

/// Two columns in a lazy stack: holdings run into the hundreds and every depiction is a `Canvas`
/// or a measured bar, so only visible rows are built. A lazy stack cannot see every row, so the
/// value column takes the width of the longest value, measured once off-screen; with tabular
/// digits the longest string is also the widest, and every depiction starts at the same x.
private struct CoinageDetailsView: View {
    let breakdown: CoinageBalanceBreakdownViewModel

    @State private var amountColumnWidth: CGFloat?

    var body: some View {
        LazyVStack(spacing: 18) {
            ForEach(breakdown.holdings) { holding in
                HStack(spacing: 12) {
                    amountText(holding.amount)
                        .frame(width: amountColumnWidth, alignment: .trailing)

                    switch holding.status {
                    case let .coin(model):
                        CoinStatusView(model: model)
                    case let .voucher(model):
                        VoucherStatusView(model: model)
                    }
                }
            }
        }
        .background {
            amountText(longestAmount)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: {
                    amountColumnWidth = $0
                }
        }
    }
}

private extension CoinageDetailsView {
    var longestAmount: String? {
        breakdown.holdings.compactMap(\.amount).max { $0.count < $1.count }
    }

    func amountText(_ amount: String?) -> some View {
        Text(verbatim: amount ?? "—")
            .textStyle(.body14Regular())
            .monospacedDigit()
            .foregroundStyle(.fgPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }
}

/// One of the three figures under the summary bar.
private struct LegendEntry: Identifiable {
    let kind: CoinageLegendSwatch.Kind
    let title: String
    let value: String
    var labelAccessibilityId: (any AccessibilityIdentifying)?
    var valueAccessibilityId: (any AccessibilityIdentifying)?

    var id: String { title }
}
