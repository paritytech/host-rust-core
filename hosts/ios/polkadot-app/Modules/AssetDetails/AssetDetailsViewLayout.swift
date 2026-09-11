import SwiftUI
import ExternalAccessibility
import PolkadotUI
import DesignSystem

struct AssetDetailsView: View {
    @State var viewModel: AssetDetailsViewModelProtocol
    var isExpanded: Bool = false
    var onCardTapped: () -> Void
    var onCollapse: (() -> Void)?

    init(
        viewModel: AssetDetailsViewModelProtocol = AssetDetailsViewModel(),
        isExpanded: Bool = false,
        onCardTapped: @escaping () -> Void,
        onCollapse: (() -> Void)? = nil
    ) {
        _viewModel = State(initialValue: viewModel)
        self.isExpanded = isExpanded
        self.onCardTapped = onCardTapped
        self.onCollapse = onCollapse
    }

    var body: some View {
        DSExpandableCardLayout(
            isExpanded: isExpanded,
            onCollapse: onCollapse,
            card: { headerCard },
            details: { expandedBody }
        )
        .safeAreaInset(edge: .bottom) {
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
            if viewModel.showsBackupNotification {
                backupCard()
            } else {
                actions()
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
                if let breakdown = viewModel.coinageBreakdown,
                   viewModel.balanceCardModel != nil {
                    CoinageBalanceBreakdownView(
                        breakdown: breakdown,
                        onMakeAllVouchersReady: viewModel.onMakeAllVouchersReady
                    )
                }
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
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                DSButton(.actionSendCash, leadingIcon: .iconArrowUp16, expands: true) {
                    viewModel.onSendMoney?()
                }
                .accessibilityId(AccessibilityID.Wallet.sendPaymentButton)

                topUpButton()
            }
        }
    }

    private func topUpButton() -> some View {
        Button {
            viewModel.onTopUp?()
        } label: {
            Group {
                if viewModel.isTopUpInProgress {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.fgPrimaryInverted)
                } else {
                    Image(.add24)
                        .renderingMode(.template)
                }
            }
            .frame(width: 56, height: 56)
            .foregroundStyle(Color.fgPrimaryInverted)
            .background(.bgActionPrimary, in: Circle())
        }
        .disabled(viewModel.isTopUpInProgress)
        .accessibilityId(AccessibilityID.Wallet.addFundsButton)
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

#if TESTNET_FEATURE
    private struct CoinageBalanceBreakdownView: View {
        let breakdown: CoinageBalanceBreakdownViewModel

        var onMakeAllVouchersReady: (() -> Void)?

        @State private var showDetails = false

        var body: some View {
            VStack(spacing: 12) {
                Text(verbatim: "Coinage Balance")
                    .textStyle(.title16SemiBold())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityId(AccessibilityID.Wallet.coinageHeader)

                BreakdownRow(
                    title: "Total Balance",
                    value: breakdown.totalBalance,
                    labelAccessibilityId: AccessibilityID.Wallet.coinageTotalBalanceLabel,
                    valueAccessibilityId: AccessibilityID.Wallet.coinageTotalBalanceValue
                )
                BreakdownRow(
                    title: "Spendable Balance",
                    value: breakdown.spendableBalance,
                    labelAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceLabel,
                    valueAccessibilityId: AccessibilityID.Wallet.coinageSpendableBalanceValue
                )
                BreakdownRow(
                    title: "Pending Balance",
                    value: breakdown.pendingBalance,
                    labelAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceLabel,
                    valueAccessibilityId: AccessibilityID.Wallet.coinagePendingBalanceValue
                )

                Divider()

                BreakdownRow(title: "Coins", value: "\(breakdown.coinCount)")
                BreakdownRow(title: "Vouchers", value: "\(breakdown.voucherCount)")

                if let onMakeAllVouchersReady {
                    Button {
                        onMakeAllVouchersReady()
                    } label: {
                        Text(verbatim: "Make all vouchers ready")
                            .textStyle(.body14SemiBold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.fgPrimaryInverted)
                    }
                    .background(.bgActionPrimary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityId(AccessibilityID.Wallet.makeVouchersReadyButton)
                }

                Button {
                    withAnimation { showDetails.toggle() }
                } label: {
                    HStack {
                        Text(verbatim: showDetails ? "Hide Details" : "Show Details")
                            .textStyle(.body14SemiBold())
                        Image(systemName: showDetails ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(.fgPrimary)
                }

                if showDetails {
                    CoinageDetailsView(breakdown: breakdown)
                }
            }
            .padding(16)
            .background(.bgSurfaceContainer, in: RoundedRectangle(cornerRadius: 24))
        }
    }

    private struct CoinageDetailsView: View {
        let breakdown: CoinageBalanceBreakdownViewModel

        var body: some View {
            VStack(spacing: 16) {
                if !breakdown.coinDetails.isEmpty {
                    VStack(spacing: 8) {
                        Text(verbatim: "Coins")
                            .textStyle(.body14SemiBold())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(breakdown.coinDetails) { coin in
                            CoinDetailRow(coin: coin)
                        }
                    }
                }

                if !breakdown.voucherDetails.isEmpty {
                    VStack(spacing: 8) {
                        Text(verbatim: "Vouchers")
                            .textStyle(.body14SemiBold())
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(breakdown.voucherDetails) { voucher in
                            VoucherDetailRow(voucher: voucher)
                        }
                    }
                }
            }
        }
    }

    private struct CoinDetailRow: View {
        let coin: CoinDetailViewModel

        var body: some View {
            VStack(spacing: 4) {
                HStack {
                    Text(verbatim: "#\(coin.id)")
                        .textStyle(.caption12Regular())
                        .foregroundStyle(.fgSecondary)
                    Spacer()
                    Text(verbatim: coin.state)
                        .textStyle(.caption12Regular())
                        .foregroundStyle(coin.state == "Available" ? Color
                            .fgPrimary : .fgSecondary)
                }
                HStack {
                    BreakdownRow(title: "Value", value: coin.exponent)
                    Divider().background(.fgPrimary)
                    BreakdownRow(title: "Age", value: coin.age)
                }
            }
            .padding(8)
            .background(.bgSurfaceNested, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private struct VoucherDetailRow: View {
        let voucher: VoucherDetailViewModel

        var body: some View {
            VStack(spacing: 4) {
                HStack {
                    Text(verbatim: "#\(voucher.id)")
                        .textStyle(.caption12Regular())
                        .foregroundStyle(.fgSecondary)
                    Spacer()
                    Text(verbatim: voucher.state)
                        .textStyle(.caption12Regular())
                        .foregroundStyle(voucher.state == "Ready" ? .fgPrimary : .fgSecondary)
                }
                BreakdownRow(title: "Value", value: voucher.exponent)
                BreakdownRow(title: "Allocated", value: voucher.allocatedAt)
                BreakdownRow(title: "Ready at", value: voucher.readyAt)
            }
            .padding(8)
            .background(.bgSurfaceNested, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private struct BreakdownRow: View {
        let title: String
        let value: String
        var labelAccessibilityId: (any AccessibilityIdentifying)?
        var valueAccessibilityId: (any AccessibilityIdentifying)?

        var body: some View {
            HStack {
                Text(title)
                    .textStyle(.body14Regular())
                    .foregroundStyle(.fgSecondary)
                    .accessibilityId(labelAccessibilityId)
                Spacer()
                Text(value)
                    .textStyle(.body14SemiBold())
                    .accessibilityId(valueAccessibilityId)
            }
        }
    }
#endif
