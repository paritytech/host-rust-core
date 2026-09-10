package io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.last

interface ExternalPaymentService {
    suspend fun initiatePayment(
        origin: PaymentOrigin,
        amount: Balance,
        destination: AccountId,
    ): Result<PaymentId>

    fun subscribePaymentStatus(
        origin: PaymentOrigin,
        paymentId: PaymentId,
    ): Flow<PaymentStatus>
}

suspend fun ExternalPaymentService.awaitTransferOutcome(
    origin: PaymentOrigin,
    paymentId: PaymentId,
): Result<Unit> = runCancellableCatching {
    val terminalStatus = subscribePaymentStatus(origin = origin, paymentId = paymentId).last()
    when (terminalStatus) {
        is PaymentStatus.Completed -> Unit
        is PaymentStatus.Failed -> throw ExternalPaymentFailedException(terminalStatus.reason)
        is PaymentStatus.Processing -> error("Payment did not reach terminal state")
    }
}

class ExternalPaymentFailedException(reason: String) : RuntimeException(reason)
