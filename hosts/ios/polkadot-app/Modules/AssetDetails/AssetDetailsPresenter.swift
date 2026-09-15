import Foundation
import Foundation_iOS
import SubstrateSdk
import PolkadotUI
import Coinage
import ChainRegistry
import Products

@MainActor
final class AssetDetailsPresenter {
    weak var view: AssetDetailsViewProtocol?

    let wireframe: AssetDetailsWireframeProtocol
    let interactor: AssetDetailsInteractorInputProtocol?

    let viewModelFactory: WalletCardViewModelFactoryProtocol
    private let balanceFormatterFactory: AssetBalanceFormatterFactoryProtocol
    private var balanceFormatter: LocalizableDecimalFormatting?
    private var priceFormatter: LocalizableDecimalFormatting?
    private lazy var fundingConfiguration: AssetFundingStatusView.Configuration =
        .fundingDigitalDollarConfiguration()

    private let chainAsset: ChainAsset
    private var balance: Decimal = 0
    private var lockedAmount: Decimal = 0
    private var coins: [TrackedCoin] = []
    private var vouchers: [TrackedVoucher] = []
    private var price: PriceData?
    let logger: LoggerProtocol

    init(
        interactor: AssetDetailsInteractorInputProtocol,
        wireframe: AssetDetailsWireframeProtocol,
        viewModelFactory: WalletCardViewModelFactoryProtocol,
        logger: LoggerProtocol,
        chainAsset: ChainAsset,
        balanceFormatterFactory: AssetBalanceFormatterFactoryProtocol = AssetBalanceFormatterFactory()
    ) {
        self.interactor = interactor
        self.wireframe = wireframe
        self.viewModelFactory = viewModelFactory
        self.logger = logger
        self.chainAsset = chainAsset
        self.balanceFormatterFactory = balanceFormatterFactory
    }

    private func provideAssets() {
        let viewModels = [viewModelFactory.createAssetViewModel(from: chainAsset)]
        view?.didSetCards(viewModels: viewModels)
    }

    private func provideAssetBalance() {
        let balanceViewModelFactory = PrimitiveBalanceViewModelFactory(
            targetAssetInfo: chainAsset.asset.digitalDollarDisplayInfo.withoutSymbol,
            formatterFactory: balanceFormatterFactory
        )

        let balanceViewModel = balanceViewModelFactory.balanceFromPrice(
            balance,
            priceData: price
        )
        .value(for: .current)

        view?.didReceiveData(viewModel: .token(balanceViewModel), index: 0)

        guard lockedAmount > 0 else {
            view?.didReceive(lockedAmount: nil)
            return
        }

        let lockedViewModel = balanceViewModelFactory.balanceFromPrice(
            lockedAmount,
            priceData: price
        )
        .value(for: .current)

        view?.didReceive(lockedAmount: lockedViewModel)
    }
}

extension AssetDetailsPresenter: AssetDetailsPresenterProtocol {
    func onBackupSync() {
        interactor?.triggerSync()
    }

    func onBackupCancel() {
        wireframe.showCancelBackupConfirmation(from: view) { [weak self] in
            self?.interactor?.cancelBackupNotification()
        }
    }

    func onBackupWhyUpdate() {
        wireframe.showWhyBackupUpdate(from: view)
    }

    func setup() {
        provideAssets()
        provideAssetBalance()
        interactor?.setup()
    }

    func onSendMoney() {
        wireframe.showTransfer(from: view, chainAsset: chainAsset)
    }

    func onAddMoney() {
        wireframe.showAddTokens(from: view)
    }

    func onFundingCompletedAction() {
        interactor?.removeCompletedFiatOnrampTransactions()
    }

    func onFundingFailedAction() {
        interactor?.removeFailedFiatOnrampTransactions()
    }

    func onTopUp() {
        view?.didReceive(topUpLoading: true)

        interactor?.openTopUpProduct()
    }

    #if TESTNET_FEATURE
        func onTestnetTopUp() {
            view?.didReceive(testnetTopUpLoading: true)

            interactor?.topUp()
        }

        func onMakeAllVouchersReady() {
            interactor?.makeAllVouchersReady()
        }
    #endif
}

extension AssetDetailsPresenter: AssetDetailsInteractorOutputProtocol {
    func didResolveTopUpProduct(_ result: Result<ProductPage, Error>) {
        view?.didReceive(topUpLoading: false)

        switch result {
        case let .success(page):
            wireframe.showProduct(page: page)
        case let .failure(error):
            wireframe.present(error: error, from: view)
        }
    }

    #if TESTNET_FEATURE
        func didCompleteTopUp(_ result: Result<Void, Error>) {
            view?.didReceive(testnetTopUpLoading: false)

            guard case let .failure(error) = result else {
                return
            }

            wireframe.present(error: error, from: view)
        }

        func didReceive(coins: [TrackedCoin], vouchers: [TrackedVoucher]) {
            self.coins = coins
            self.vouchers = vouchers
            provideCoinageBreakdown()
        }
    #endif

    func didReceive(fiatOnrampStatuses: Set<FiatOnrampTransactionStatusPayload>) {
        provideFundingStates(from: fiatOnrampStatuses)
    }

    func didReceive(balance: Decimal) {
        self.balance = balance
        provideAssetBalance()
        #if TESTNET_FEATURE
            provideCoinageBreakdown()
        #endif
    }

    func didReceive(lockedAmount: Decimal) {
        self.lockedAmount = lockedAmount
        provideAssetBalance()
        #if TESTNET_FEATURE
            provideCoinageBreakdown()
        #endif
    }

    func didReceive(price: PriceData?) {
        self.price = price
        provideAssetBalance()
    }

    func didFail(recovery error: Error) {
        wireframe.present(error: error, from: view)
    }

    func didReceive(isRecoveryInProgress: Bool) {
        view?.didReceive(isRecoveryInProgress: isRecoveryInProgress)
    }

    func didCompleteRecovery() {
        view?.didShowBackupNotification()
    }

    func didClearBackupNotification() {
        view?.didHideBackupNotification()
    }
}

private extension AssetDetailsPresenter {
    func provideFundingStates(from statuses: Set<FiatOnrampTransactionStatusPayload>) {
        let sortedStatuses = statuses.sorted { lhs, rhs in
            lhs.id.value < rhs.id.value
        }

        let states: [AssetFundingStatusView.FundingState] = sortedStatuses.map { status in
            switch status.status {
            case .funding:
                .init(id: status.id.value, status: .waiting)
            case let .inProgress(remainedTime, inAmount, outAmount):
                .init(
                    id: status.id.value,
                    status: .inProgress(
                        totalSeconds: Int(ceil(remainedTime)),
                        amountIn: formatAmount(inAmount),
                        amountOut: formatUsdAmount(outAmount)
                    )
                )
            case let .completed(inAmount, outAmount):
                .init(
                    id: status.id.value,
                    status: .completed(
                        amountIn: formatAmount(inAmount),
                        amountOut: formatUsdAmount(outAmount)
                    )
                )
            case .failed:
                .init(id: status.id.value, status: .failed)
            }
        }

        view?.didReceive(fundingStates: states)
    }

    func formatAmount(_ amount: Balance) -> String {
        let formatter = getBalanceFormatter()
        let decimalAmount = amount.decimal(assetInfo: chainAsset.assetDisplayInfo)
        return formatter.stringFromDecimal(decimalAmount) ?? ""
    }

    func getBalanceFormatter() -> LocalizableDecimalFormatting {
        if let balanceFormatter {
            return balanceFormatter
        }

        let formatter = balanceFormatterFactory
            .createTokenFormatter(for: chainAsset.assetDisplayInfo)
            .value(for: .current)

        balanceFormatter = formatter

        return formatter
    }

    func getPriceFormatter() -> LocalizableDecimalFormatting {
        if let priceFormatter {
            return priceFormatter
        }

        let formatter = balanceFormatterFactory
            .createAssetPriceFormatter(for: .usd)
            .value(for: .current)

        priceFormatter = formatter

        return formatter
    }

    func formatUsdAmount(_ amount: Balance) -> String {
        let formatter = getPriceFormatter()
        let decimalAmount = amount.decimal(assetInfo: chainAsset.assetDisplayInfo)
        return formatter.stringFromDecimal(decimalAmount) ?? ""
    }
}

#if TESTNET_FEATURE
    private extension AssetDetailsPresenter {
        func provideCoinageBreakdown() {
            func formatted(from decimal: Decimal) -> String {
                let balanceViewModelFactory = PrimitiveBalanceViewModelFactory(
                    targetAssetInfo: chainAsset.asset.digitalDollarDisplayInfo,
                    formatterFactory: balanceFormatterFactory
                )
                return balanceViewModelFactory.balanceFromPrice(
                    decimal,
                    priceData: price
                )
                .value(for: .current)
                .amount
            }

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short

            // Only assets that make up the balance are counted and listed — the same inclusion rule
            // the balance uses (`TrackedCoin/TrackedVoucher.isBalanceCounted`).
            let countedCoins = coins.filter(\.isBalanceCounted)
            let countedVouchers = vouchers.filter(\.isBalanceCounted)

            let coinDetails = countedCoins
                .sorted { $0.coin.derivationIndex < $1.coin.derivationIndex }
                .map { tracked in
                    let coin = tracked.coin
                    let state = tracked.state
                    let stateLabel: String = {
                        if coin.handoffMark != .none { return "Handed off" }
                        if state.isConsumed { return "Spent" }
                        if state.isInUse { return "Reserved" }
                        if state.isMintingFailed, !coin.isOnchain { return "Minting failed" }
                        if !coin.isOnchain {
                            return "Pending mint"
                        }
                        return "Available"
                    }()
                    return CoinDetailViewModel(
                        id: coin.identifier,
                        exponent: "2^\(coin.exponent)",
                        state: stateLabel,
                        age: coin.age.map { "\($0)" } ?? "Unknown"
                    )
                }

            let voucherDetails = countedVouchers
                .sorted { $0.voucher.derivationIndex < $1.voucher.derivationIndex }
                .map { tracked in
                    let voucher = tracked.voucher
                    let stateString: String =
                        switch voucher.remoteState {
                        case .unlocated: "Unlocated"
                        case .onboarding: "Pending"
                        case .inRecycler: voucher.readyAt > .now ? "Locked" : "Ready"
                        }

                    return VoucherDetailViewModel(
                        id: voucher.identifier,
                        exponent: "2^\(voucher.exponent)",
                        state: stateString,
                        allocatedAt: dateFormatter.string(from: voucher.allocatedAt),
                        readyAt: dateFormatter.string(from: voucher.readyAt)
                    )
                }

            let spendable = balance - lockedAmount
            let breakdown = CoinageBalanceBreakdownViewModel(
                totalBalance: formatted(from: balance),
                spendableBalance: formatted(from: spendable),
                pendingBalance: formatted(from: lockedAmount),
                coinCount: countedCoins.count,
                voucherCount: countedVouchers.count,
                coinDetails: coinDetails,
                voucherDetails: voucherDetails
            )
            view?.didReceive(coinageBreakdown: breakdown)
        }
    }
#endif
