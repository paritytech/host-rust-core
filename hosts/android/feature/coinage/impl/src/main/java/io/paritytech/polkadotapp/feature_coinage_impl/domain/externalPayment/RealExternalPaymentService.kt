package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentService
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentWorkerStarter
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentId
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentOrigin
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentStatus
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.model.ExternalPayment
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.repository.ExternalPaymentRepository
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.mapNotNull
import kotlinx.coroutines.flow.transformWhile
import javax.inject.Inject

class RealExternalPaymentService @Inject constructor(
    private val repository: ExternalPaymentRepository,
    private val workerStarter: ExternalPaymentWorkerStarter,
) : ExternalPaymentService {
    override suspend fun initiatePayment(
        origin: PaymentOrigin,
        amount: Balance,
        destination: AccountId,
    ): Result<PaymentId> = runCatching {
        val payment = ExternalPayment.new(origin = origin, amount = amount, destination = destination)
        repository.insert(payment)
        workerStarter.start()
        payment.id
    }

    override fun subscribePaymentStatus(
        origin: PaymentOrigin,
        paymentId: PaymentId,
    ): Flow<PaymentStatus> = repository.observeById(paymentId)
        .mapNotNull { payment -> payment?.takeIf { it.origin == origin }?.toStatus() }
        .distinctUntilChanged()
        .transformWhile { status ->
            emit(status)
            status is PaymentStatus.Processing
        }

    private fun ExternalPayment.toStatus(): PaymentStatus = when (val s = stage) {
        ExternalPayment.Stage.Completed -> PaymentStatus.Completed
        // Money moved, so this is a completion. How much of it is the reason string's job.
        is ExternalPayment.Stage.PartiallyCompleted -> PaymentStatus.Completed
        is ExternalPayment.Stage.Failed -> PaymentStatus.Failed(s.reason)
        else -> PaymentStatus.Processing
    }
}
