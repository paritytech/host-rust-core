package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.repository

import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentId
import io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.model.ExternalPayment
import kotlinx.coroutines.flow.Flow

interface ExternalPaymentRepository {
    suspend fun insert(payment: ExternalPayment)

    suspend fun getNextPending(): ExternalPayment?

    fun observeById(id: PaymentId): Flow<ExternalPayment?>
}
