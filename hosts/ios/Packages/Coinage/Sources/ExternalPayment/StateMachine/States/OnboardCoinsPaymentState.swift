import Foundation
import StateMachine

/// Recycles selected coins into vouchers, then transitions back to plan.
struct OnboardCoinsPaymentState: StateMachineState {
    typealias StateFactory = ExternalPaymentStateFactory
    typealias PersistentValue = ExternalPayment

    let payment: ExternalPayment
    let coins: [Coin]
    let isTerminal = false

    func transit(
        with factory: ExternalPaymentStateFactory
    ) async -> AnyStateMachineState<ExternalPaymentStateFactory, ExternalPayment> {
        do {
            try await factory.recycler.recycleCoins(coins)
            return factory.makePlanState(payment: payment)
        } catch {
            return factory.makeFailedState(
                payment: payment,
                reason: error.localizedDescription
            )
        }
    }

    func memo() async -> ExternalPayment {
        var currentPayment = payment
        currentPayment.stage = .onboardCoins
        currentPayment.updatedAt = Date()
        return currentPayment
    }
}
