import Foundation
import StateMachine

/// Terminal state indicating the payment is rescheduled for later.
struct RescheduledPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let until: Date
    let isTerminal = true

    func transit(
        with _: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        AnyStateMachineState(self)
    }

    func memo() async -> ExternalPayment {
        var p = payment
        p.stage = .rescheduled
        p.readyAt = until
        p.updatedAt = Date()
        return p
    }
}
