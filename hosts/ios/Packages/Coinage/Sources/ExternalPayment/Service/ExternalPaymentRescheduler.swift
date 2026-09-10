import Foundation
import SDKLogger

/// Observes rescheduled payments and transitions them back to `.plan` when `readyAt` arrives.
///
/// For each rescheduled payment, a `Task.sleep` waits until `readyAt`,
/// then resets the payment stage to `.plan` in the store. The main
/// `ExternalPaymentService` picks it up reactively via its own store observer.
public final class ExternalPaymentRescheduler: ExternalPaymentRescheduling, @unchecked Sendable {
    let store: ExternalPaymentStoring
    let context: ExternalPaymentReschedulerContext
    let logger: SDKLoggerProtocol?

    private var observeTask: Task<Void, Never>?

    public init(
        store: ExternalPaymentStoring,
        logger: SDKLoggerProtocol? = nil
    ) {
        self.store = store
        context = ExternalPaymentReschedulerContext(logger: logger)
        self.logger = logger
    }

    public func setup() {
        observeTask = Task { [store, context, logger, weak self] in
            do {
                for try await payments in store.observeRescheduledPayments() {
                    for payment in payments {
                        await context.scheduleIfNeeded(paymentId: payment.id) { [weak self] in
                            Task { [weak self] in
                                await self?.wakeupPayment(payment)
                            }
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                logger?.error("Observing task failed: \(error)")
            }
        }
    }

    public func throttle() {
        observeTask?.cancel()
        observeTask = nil
        Task { [context] in await context.cancelAll() }
    }
}

// MARK: - Private

private extension ExternalPaymentRescheduler {
    func wakeupPayment(_ payment: ExternalPayment) async {
        let delay = max(payment.readyAt.timeIntervalSinceNow, 0)
        logger?.debug("Scheduling payment \(payment.id) wakeup in \(delay)s")

        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return // cancelled
        }

        do {
            var updated = payment
            updated.stage = .plan
            updated.readyAt = Date()
            updated.updatedAt = Date()
            try await store.save(payment: updated)
            logger?.debug("Payment \(payment.id) rescheduled back to plan")
        } catch {
            logger?.error("Failed to reschedule payment \(payment.id): \(error)")
        }

        await context.onComplete(paymentId: payment.id)
    }
}
