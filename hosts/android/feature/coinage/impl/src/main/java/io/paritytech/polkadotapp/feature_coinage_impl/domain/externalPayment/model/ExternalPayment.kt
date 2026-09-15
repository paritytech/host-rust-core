package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment.model

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentId
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.PaymentOrigin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RingVrfIndex
import java.util.UUID

data class ExternalPayment(
    val id: PaymentId,
    val origin: PaymentOrigin,
    val amount: Balance,
    val destination: AccountId,
    val stage: Stage,
    val createdAt: Long,
    val updatedAt: Long,
) {
    sealed interface Stage {
        data object EnsureVouchers : Stage

        data class OffboardVouchers(
            val selectedVoucherKeys: List<RingVrfIndex>,
            val surplus: Balance,
        ) : Stage

        data object Completed : Stage

        /** Some of the unload executed. Terminal, and reported to callers as completed. */
        data class PartiallyCompleted(val reason: String) : Stage

        data class Failed(val reason: String) : Stage
    }

    companion object {
        fun new(
            origin: PaymentOrigin,
            amount: Balance,
            destination: AccountId,
        ): ExternalPayment {
            val now = System.currentTimeMillis()
            return ExternalPayment(
                id = UUID.randomUUID().toString(),
                origin = origin,
                amount = amount,
                destination = destination,
                stage = Stage.EnsureVouchers,
                createdAt = now,
                updatedAt = now,
            )
        }
    }
}
