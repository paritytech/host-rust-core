package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.state

import io.paritytech.polkadotapp.common.data.worker.stateMachine.WorkerStateMachineState.TransitionResult
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentContext

data class CompletedPaymentState(override val context: PaymentContext) : ExternalPaymentState {
    override val id: String = "Completed"

    context(noContext: NoContext)
    override suspend fun performTransition(): TransitionResult<ExternalPaymentState> {
        return TransitionResult.StateTerminal
    }
}

/**
 * Some of the unload executed and some did not, so the destination got less than it was promised.
 *
 * Terminal, and reported to callers as completed rather than failed: money moved, and telling a caller
 * "everything failed" would be the larger lie of the two.
 */
data class PartiallyCompletedPaymentState(
    override val context: PaymentContext,
    val reason: String,
) : ExternalPaymentState {
    override val id: String = "PartiallyCompleted"

    context(noContext: NoContext)
    override suspend fun performTransition(): TransitionResult<ExternalPaymentState> {
        return TransitionResult.StateTerminal
    }
}

data class FailedPaymentState(override val context: PaymentContext, val reason: String) : ExternalPaymentState {
    override val id: String = "Failed"

    context(noContext: NoContext)
    override suspend fun performTransition(): TransitionResult<ExternalPaymentState> {
        return TransitionResult.StateTerminal
    }
}
