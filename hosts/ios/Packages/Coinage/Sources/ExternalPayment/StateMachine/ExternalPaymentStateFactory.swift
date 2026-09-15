import ExtrinsicService
import Foundation
import KeyDerivation
import SDKLogger
import StateMachine
import SubstrateOperation

/// Factory providing all dependencies and methods to create external payment states.
///
/// Passed to each state's ``StateMachineState/transit(with:)`` so states
/// can create their successors without coupling to concrete types.
final class ExternalPaymentStateFactory {
    let instanceId: CoinageInstanceId
    let planner: ExternalPaymentPlanning
    let context: DenominationBreakdownContext
    let recycler: CoinageRecyclingServicing
    let voucherService: VoucherServiceProtocol
    let voucherKeyFactory: any VoucherKeyDeriving
    let voucherMinter: any VoucherMinting
    let recyclerLoader: RecyclerReadinessLoading
    let durability: any CoinageTxServicing
    let originFactory: OriginCreating
    let quotaTracker: any UnloadQuotaTracking
    let blockNumberProvider: BlockInfoProviding
    let logger: SDKLoggerProtocol?

    init(
        instanceId: CoinageInstanceId,
        planner: ExternalPaymentPlanning,
        context: DenominationBreakdownContext,
        recycler: CoinageRecyclingServicing,
        voucherService: VoucherServiceProtocol,
        voucherKeyFactory: any VoucherKeyDeriving,
        voucherMinter: any VoucherMinting,
        recyclerLoader: RecyclerReadinessLoading,
        durability: any CoinageTxServicing,
        originFactory: OriginCreating,
        quotaTracker: any UnloadQuotaTracking,
        blockNumberProvider: BlockInfoProviding,
        logger: SDKLoggerProtocol?
    ) {
        self.instanceId = instanceId
        self.planner = planner
        self.context = context
        self.recycler = recycler
        self.voucherService = voucherService
        self.voucherKeyFactory = voucherKeyFactory
        self.voucherMinter = voucherMinter
        self.recyclerLoader = recyclerLoader
        self.durability = durability
        self.originFactory = originFactory
        self.quotaTracker = quotaTracker
        self.blockNumberProvider = blockNumberProvider
        self.logger = logger
    }
}

// MARK: - State Creation

extension ExternalPaymentStateFactory {
    typealias ErasedState = AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment>

    func makePlanState(payment: ExternalPayment) -> ErasedState {
        AnyStateMachineState(PlanPaymentState(payment: payment))
    }

    func makeOnboardCoinsState(payment: ExternalPayment, coins: [Coin]) -> ErasedState {
        AnyStateMachineState(OnboardCoinsPaymentState(payment: payment, coins: coins))
    }

    func makeOffboardVouchersState(
        payment: ExternalPayment,
        vouchers: [Voucher]
    ) -> ErasedState {
        AnyStateMachineState(OffboardVouchersPaymentState(
            payment: payment,
            vouchers: vouchers
        ))
    }

    func makeCompletedState(payment: ExternalPayment) -> ErasedState {
        AnyStateMachineState(CompletedPaymentState(payment: payment))
    }

    func makeFailedState(payment: ExternalPayment, reason: String) -> ErasedState {
        AnyStateMachineState(FailedPaymentState(payment: payment, reason: reason))
    }

    func makePartiallyCompletedState(payment: ExternalPayment, reason: String) -> ErasedState {
        AnyStateMachineState(PartiallyCompletedPaymentState(payment: payment, reason: reason))
    }

    func makeRescheduledState(payment: ExternalPayment, until: Date) -> ErasedState {
        AnyStateMachineState(RescheduledPaymentState(payment: payment, until: until))
    }

    /// Restores a state from a persisted ``ExternalPayment`` memo.
    func stateFromMemo(payment: ExternalPayment) -> ErasedState {
        switch payment.stage {
        case .plan:
            makePlanState(payment: payment)
        case .onboardCoins:
            // we don't have information about coins in the memo since the whole coinage state might be changed
            // as actual spending have not been started yet we fallback to planing again
            makePlanState(payment: payment)
        case .offboardVouchers:
            // Re-enter offboarding with no plan-carried vouchers: the state re-joins the durability
            // group this payment already registered (keyed by payment id) and awaits its real
            // outcome, or re-plans if nothing was registered before the crash.
            makeOffboardVouchersState(payment: payment, vouchers: [])
        case .completed:
            makeCompletedState(payment: payment)
        case .failed:
            makeFailedState(payment: payment, reason: payment.failureReason ?? "Unknown")
        case .rescheduled:
            makeRescheduledState(payment: payment, until: payment.readyAt)
        case .partiallyCompleted:
            makePartiallyCompletedState(payment: payment, reason: payment.failureReason ?? "Partial")
        }
    }
}
