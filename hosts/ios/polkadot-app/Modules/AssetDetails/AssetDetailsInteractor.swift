import UIKit
import Operation_iOS
import OperationExt
import Foundation
import SubstrateSdk
import StructuredConcurrency
import Coinage
import CommonService
import KeyDerivation
import AsyncExtensions
import AsyncAlgorithms
import ChainRegistry
import EventCenter
import BackgroundExecution
import Products
import UIKitExt

final class AssetDetailsInteractor: AnyProviderAutoCleaning {
    weak var presenter: AssetDetailsInteractorOutputProtocol?

    let priceLocalSubscriptionFactory: PriceProviderFactoryProtocol
    let chainAsset: ChainAsset

    private let fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol
    private var fiatOnrampTrackingTask: Task<Void, Never>?

    private var balanceSubscriptionTask: Task<Void, Error>?
    private var priceProvider: StreamableProvider<PriceData>?
    private var priceSubscriptionTask: Task<Void, Never>?
    private let coinageService: CoinageServicing
    private let coinageBackupSyncService: any CoinageBackupSyncServicing
    private let balanceSyncStateStorage: BalanceSyncStateStoring
    private let eventCenter: EventCenterProtocol

    private var recoveryStateTask: Task<Void, Error>?

    private let fundingDomainProvider: FundingDomainProviding
    private var rampProductTasks: [RampAction: Task<Void, Never>] = [:]

    #if TESTNET_FEATURE
        var backgroundExecutor: BackgroundExecuting?
        var voucherRepository: AnyDataProviderRepository<Voucher>?
        var topupService: TopUpService?
        var faucetTask: Task<Void, Error>?
    #endif

    init(
        priceLocalSubscriptionFactory: PriceProviderFactoryProtocol,
        fiatOnrampTrackingService: FiatOnrampTrackingServiceProtocol,
        chainAsset: ChainAsset,
        coinageService: CoinageServicing,
        coinageBackupSyncService: any CoinageBackupSyncServicing,
        balanceSyncStateStorage: BalanceSyncStateStoring,
        fundingDomainProvider: FundingDomainProviding,
        eventCenter: EventCenterProtocol = EventCenter.shared
    ) {
        self.priceLocalSubscriptionFactory = priceLocalSubscriptionFactory
        self.fiatOnrampTrackingService = fiatOnrampTrackingService
        self.chainAsset = chainAsset
        self.coinageService = coinageService
        self.coinageBackupSyncService = coinageBackupSyncService
        self.balanceSyncStateStorage = balanceSyncStateStorage
        self.eventCenter = eventCenter
        self.fundingDomainProvider = fundingDomainProvider
    }

    deinit {
        fiatOnrampTrackingTask?.cancel()
        balanceSubscriptionTask?.cancel()
        recoveryStateTask?.cancel()
        priceSubscriptionTask?.cancel()
        rampProductTasks.values.forEach { $0.cancel() }
    }
}

extension AssetDetailsInteractor: AssetDetailsInteractorInputProtocol {
    func setup() {
        if balanceSyncStateStorage.isRestorePending {
            Task { @MainActor [weak self] in
                self?.presenter?.didCompleteRecovery()
            }
        }

        eventCenter.add(observer: self)
        subscribeToFiatOnrampTracking()
        subscribeToPrice()
        subscribeToBalances()
        subscribeToRecoveryState()

        provideDenominationContext()
    }

    func triggerSync() {
        coinageBackupSyncService.triggerRecovery()
    }

    func cancelBackupNotification() {
        balanceSyncStateStorage.isRestorePending = false
    }

    func removeCompletedFiatOnrampTransactions() {
        fiatOnrampTrackingService.removeCompletedTransactions()
    }

    func removeFailedFiatOnrampTransactions() {
        fiatOnrampTrackingService.removeFailedTransactions()
    }

    func openRampProduct(_ action: RampAction) {
        rampProductTasks[action]?.cancel()
        rampProductTasks[action] = Task { [weak presenter, fundingDomainProvider] in
            do {
                let page = try await action.resolvePage(using: fundingDomainProvider)
                await presenter?.didResolveRampProduct(action, result: .success(page))
            } catch {
                await presenter?.didResolveRampProduct(action, result: .failure(error))
            }
        }
    }

    #if TESTNET_FEATURE
        func topUp() {
            faucetTask?.cancel()
            faucetTask = Task { [weak presenter, topupService, backgroundExecutor, coinageService] in
                guard let topupService, let backgroundExecutor else {
                    return
                }
                do {
                    guard let amount = Decimal(5).toSubstrateAmount(precision: chainAsset.asset.decimalPrecision) else {
                        return
                    }

                    let randomSeed = try Data.randomOrError(of: 32)
                    let depositWallet = try DynamicDerivedWallet(seedBytes: randomSeed)

                    try await backgroundExecutor.execute {
                        try await markStallActivity("Topup") {
                            try await topupService.topUp(depositWallet, amount: .plank(amount))
                            try await coinageService.loadVouchers(amount: amount, externalAssetHolder: depositWallet)
                        }
                    }

                    await presenter?.didCompleteTopUp(.success(()))
                } catch {
                    await presenter?.didCompleteTopUp(.failure(error))
                }
            }
        }

        func makeAllVouchersReady() {
            Task { [weak self] in
                guard let self, let voucherRepository else { return }
                do {
                    let vouchers = try await voucherRepository
                        .fetchAllOperation(with: RepositoryFetchOptions())
                        .asyncExecute()

                    let updatedVouchers = vouchers.map { voucher in
                        guard voucher.readyAt > .now else { return voucher }

                        // Every field has to be carried over: this is a whole-model save, so any
                        // omission is written back as the initialiser's default.
                        return Voucher(
                            exponent: voucher.exponent,
                            derivationIndex: voucher.derivationIndex,
                            allocatedAt: voucher.allocatedAt,
                            readyAt: .now,
                            remoteState: voucher.remoteState,
                            recyclerFungibility: voucher.recyclerFungibility,
                            maxRecyclerFungibility: voucher.maxRecyclerFungibility,
                            publicKey: voucher.publicKey
                        )
                    }

                    try await voucherRepository
                        .saveOperation({ updatedVouchers }, { [] })
                        .asyncExecute()
                } catch {
                    Logger.shared.error("Failed to make all vouchers ready: \(error)")
                }
            }
        }

    #endif

    /// Needed to price individual holdings, so a failure here degrades to amount-less rows rather
    /// than to no rows.
    private func provideDenominationContext() {
        Task { [weak presenter, coinageService] in
            do {
                let context = try await coinageService.denominationContext()
                await presenter?.didReceive(denominationContext: context)
            } catch {
                Logger.shared.error("Denomination context unavailable: \(error)")
            }
        }
    }

    /// Reads the balance and the holdings behind it as one value. Two subscriptions would let the
    /// figures and the rows come from different evaluations, so the breakdown would briefly show
    /// totals its own rows do not add up to.
    private func subscribeToBalances() {
        balanceSubscriptionTask?.cancel()
        balanceSubscriptionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let balanceService = try await coinageService.coinageBalanceService()
                let context = balanceService.denominationContext
                for try await summary in balanceService.summaryStream {
                    try Task.checkCancellation()
                    let balance = summary.balance
                    // Locked is everything the strategy will not part with: pending plus any
                    // gaining-privacy funds the strategy won't release on confirmation.
                    let locked = balance.total - balance.available
                    await presenter?.didReceive(balance: context.decimal(fromPlanks: balance.total))
                    await presenter?.didReceive(lockedAmount: context.decimal(fromPlanks: locked))

                    // The breakdown shows the domain's own three buckets rather than
                    // re-deriving them, and the holdings that produced them arrive in the same
                    // value — so its figures and the bar below them cannot disagree.
                    await presenter?.didReceive(
                        coinageAmounts: CoinageAmounts(
                            total: context.decimal(fromPlanks: balance.total),
                            availableNow: context.decimal(fromPlanks: balance.availablePrivate),
                            gainingPrivacy: context.decimal(
                                fromPlanks: balance.gainingPrivacy.amount
                            ),
                            pending: context.decimal(fromPlanks: balance.pending)
                        ),
                        holdings: summary.holdings
                    )
                }
            } catch {
                Logger.shared.error("Balance stream failed: \(error)")
            }
        }
    }
}

private extension AssetDetailsInteractor {
    func subscribeToRecoveryState() {
        recoveryStateTask?.cancel()
        recoveryStateTask = Task { [weak presenter, coinageBackupSyncService] in
            let stream = coinageBackupSyncService.stateStream
            for try await state in stream {
                switch state {
                case .inProgress:
                    await presenter?.didReceive(isRecoveryInProgress: true)
                case let .failed(error):
                    await presenter?.didReceive(isRecoveryInProgress: false)
                    await presenter?.didFail(recovery: error)
                case .idle:
                    await presenter?.didReceive(isRecoveryInProgress: false)
                case .completed:
                    await presenter?.didReceive(isRecoveryInProgress: false)
                }
            }
        }
    }

    func subscribeToFiatOnrampTracking() {
        fiatOnrampTrackingTask?.cancel()
        fiatOnrampTrackingTask = Task { [weak self] in
            guard let self else {
                return
            }

            let stream = await fiatOnrampTrackingService.subscribeToTransactionStatuses()

            do {
                for try await statuses in stream {
                    await presenter?.didReceive(fiatOnrampStatuses: statuses)
                }
            } catch {
                // No-op: tracking updates are best-effort
            }
        }
    }

    private func subscribeToPrice() {
        guard let priceId = chainAsset.asset.priceId else {
            return
        }
        priceProvider = priceLocalSubscriptionFactory.getPriceStreamableProvider(
            for: priceId,
            currency: .usd
        )

        priceSubscriptionTask?.cancel()
        priceSubscriptionTask = Task { [weak self] in
            guard let self, let priceProvider else { return }
            do {
                for try await changes in priceProvider.asyncStream() {
                    let price = changes.reduceToLastChange()
                    await MainActor.run {
                        self.presenter?.didReceive(price: price)
                    }
                }
            } catch {
                Logger.shared.error("Price subscription failed: \(error)")
            }
        }
    }
}

extension AssetDetailsInteractor: AppEventVisiting {
    func processBalanceSyncState(event _: BalanceSyncState) {
        let pending = balanceSyncStateStorage.isRestorePending
        Task { @MainActor [weak self] in
            if pending {
                self?.presenter?.didCompleteRecovery()
            } else {
                self?.presenter?.didClearBackupNotification()
            }
        }
    }
}

extension FundingDomainError: ErrorContentConvertible {
    func toErrorContent() -> ErrorContent {
        ErrorContent(
            title: String(localized: .Common.error),
            message: String(localized: .Products.topUpErrorMessage)
        )
    }
}
