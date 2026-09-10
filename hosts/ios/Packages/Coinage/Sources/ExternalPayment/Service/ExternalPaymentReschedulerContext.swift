import Foundation
import SDKLogger

/// Actor managing sleep tasks for rescheduled payments.
///
/// Each rescheduled payment gets a dedicated `Task.sleep` that wakes up
/// at `readyAt` and transitions the payment back to `.plan`.
actor ExternalPaymentReschedulerContext {
    private var tasks: [String: Task<Void, Never>] = [:]
    private let logger: SDKLoggerProtocol?

    init(logger: SDKLoggerProtocol? = nil) {
        self.logger = logger
    }

    /// Schedules a wakeup for the given payment if not already scheduled.
    func scheduleIfNeeded(
        paymentId: String,
        execute: @escaping @Sendable () -> Task<Void, Never>
    ) {
        guard tasks[paymentId] == nil else { return }
        tasks[paymentId] = execute()
    }

    /// Called when the wakeup completes (payment reset to .plan).
    func onComplete(paymentId: String) {
        tasks[paymentId] = nil
    }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
