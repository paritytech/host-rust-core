import Foundation
import SDKLogger
import StateMachine

/// Unloads vouchers to external asset and transfers to destination.
///
/// Delegates to ``OffboardVouchersForPaymentService``; durability tracks the resulting asset state.
struct OffboardVouchersPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let vouchers: [Voucher]
    let isTerminal = false

    func transit(
        with factory: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        let service = OffboardVouchersForPaymentService(
            instanceId: factory.instanceId,
            voucherKeyFactory: factory.voucherKeyFactory,
            voucherMinter: factory.voucherMinter,
            recyclerLoader: factory.recyclerLoader,
            txService: factory.durability,
            originFactory: factory.originFactory,
            quotaTracker: factory.quotaTracker,
            blockNumberProvider: factory.blockNumberProvider,
            denominationContext: factory.context,
            logger: factory.logger
        )

        do {
            // Before committing, pick the path:
            // - a group is already registered (crash re-entry): re-join and await it; the
            //   plan-carried vouchers are irrelevant since the inputs are already claimed.
            // - nothing registered yet: we must register, so the plan must still be valid — every
            //   selected voucher still selectable. A stale or crash-lost plan re-plans instead of
            //   failing, because the funds are still there.
            if try await !service.hasPendingGroup(for: payment) {
                guard !vouchers.isEmpty, try await allSelectable(vouchers, factory: factory) else {
                    return factory.makePlanState(payment: payment)
                }
            }

            let outcome = try await service.execute(
                payment: payment,
                vouchers: vouchers
            )
            switch outcome {
            case .success:
                return factory.makeCompletedState(payment: payment)
            case let .partialSuccess(executed, total):
                return factory.makePartiallyCompletedState(
                    payment: payment,
                    reason: "\(executed) of \(total) unload transactions executed"
                )
            case .failed:
                return factory.makeFailedState(
                    payment: payment,
                    reason: "no unload transaction executed"
                )
            }
        } catch {
            return factory.makeFailedState(
                payment: payment,
                reason: error.localizedDescription
            )
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .offboardVouchers
        currentPayment.updatedAt = Date()
        return currentPayment
    }

    /// Whether every planned voucher is still selectable right now — the plan may have gone stale
    /// (a voucher spent or recycled) since it was picked.
    private func allSelectable(
        _ vouchers: [Voucher],
        factory: ExternalPaymentStateFactory
    ) async throws -> Bool {
        let selectable = try await Set(
            factory.voucherService.fetchAllTracked()
                .filter(\.isSelectable)
                .map(\.voucher.derivationIndex)
        )
        return vouchers.allSatisfy { selectable.contains($0.derivationIndex) }
    }
}
