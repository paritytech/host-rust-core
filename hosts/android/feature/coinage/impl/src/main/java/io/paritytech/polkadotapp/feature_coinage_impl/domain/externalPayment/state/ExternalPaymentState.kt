package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentContext

/**
 * The external-payment state machine carries no per-transition context receiver; `NoContext`
 * is an alias for [Unit] that makes `context(NoContext)` self-documenting at every state.
 */
typealias NoContext = Unit

/**
 * State machine for a single [io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentId].
 *
 * Persistence uses a dedicated DB row per payment (see ExternalPaymentLocal);
 * the stage column on that row is the discriminator used to rebuild the appropriate
 * state instance (with assisted-injected dependencies) on worker restart.
 *
 * States hold their own dependencies via @AssistedInject and construct next states via the
 * injected AssistedFactory of the target state — hence no transition context is needed.
 */
sealed interface ExternalPaymentState : WorkerStateMachineState<ExternalPaymentState, NoContext> {
    val context: PaymentContext
}
