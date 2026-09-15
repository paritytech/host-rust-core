package io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher

sealed interface ExternalPaymentPlan {
    class Ready(val offboarding: VoucherOffboarding) : ExternalPaymentPlan {
        override fun toString(): String {
            return "Ready(vouchers=${offboarding.vouchers.size}, surplus=${offboarding.surplus})"
        }
    }

    class LoadCoins(val coinsToLoad: List<Coin>) : ExternalPaymentPlan {
        override fun toString(): String {
            return "LoadCoins(coins=${coinsToLoad.size})"
        }
    }

    data class NeedsDelayedRetry(val reason: DelayReason) : ExternalPaymentPlan

    data class NotEnoughAmount(
        val activeVouchers: Balance,
        val activeCoins: Balance,
        val deficitToCoverWithCoins: Balance,
    ) : ExternalPaymentPlan

    enum class DelayReason {
        VOUCHERS_NOT_READY, COINS_NOT_READY,
    }
}

class VoucherOffboarding(
    val vouchers: List<RecyclerVoucher>,
    val surplus: Balance,
)
