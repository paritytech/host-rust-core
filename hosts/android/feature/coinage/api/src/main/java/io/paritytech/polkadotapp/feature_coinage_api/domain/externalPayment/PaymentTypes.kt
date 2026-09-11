package io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.AccountId

typealias PaymentId = String
typealias PaymentOrigin = String

data class PaymentContext(
    val id: PaymentId,
    val origin: PaymentOrigin,
    val amount: Balance,
    val destination: AccountId,
)

sealed interface PaymentStatus {
    data object Processing : PaymentStatus
    data object Completed : PaymentStatus
    data class Failed(val reason: String) : PaymentStatus
}
