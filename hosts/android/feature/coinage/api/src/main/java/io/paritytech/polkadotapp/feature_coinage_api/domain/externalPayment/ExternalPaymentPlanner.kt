package io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher

interface ExternalPaymentPlanner {
    suspend fun plan(amount: Balance): Result<ExternalPaymentPlan>

    /**
     * Picks a subset of [availableVouchers] that reaches [target] amount. Used after loading extra coins
     * into vouchers, when the plan was [ExternalPaymentPlan.LoadCoins] and we now need to
     * re-select from the newly-matured set.
     * @return failure in case total balance of [availableVouchers] is not sufficient to cover [target]
     */
    suspend fun pickOffboarding(
        availableVouchers: List<RecyclerVoucher>,
        target: Balance,
    ): Result<VoucherOffboarding>
}
