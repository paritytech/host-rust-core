package io.paritytech.polkadotapp.feature_coinage_impl.domain.externalPayment

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.CoinageBalanceConversionContext
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.totalBalance
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentPlan
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentPlan.DelayReason
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.ExternalPaymentPlanner
import io.paritytech.polkadotapp.feature_coinage_api.domain.externalPayment.VoucherOffboarding
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Coin
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerVoucher
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageBalanceConverterUseCase
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.CoinageAssetSelector
import io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling.SpendScope
import javax.inject.Inject

class RealExternalPaymentPlanner @Inject constructor(
    private val assetSelector: CoinageAssetSelector,
    private val coinageBalanceConverterUseCase: CoinageBalanceConverterUseCase,
) : ExternalPaymentPlanner {
    override suspend fun plan(amount: Balance): Result<ExternalPaymentPlan> = runCancellableCatching {
        val converter = coinageBalanceConverterUseCase.create().getOrThrow()
        with(converter) { determinePlan(amount) }
    }

    override suspend fun pickOffboarding(
        availableVouchers: List<RecyclerVoucher>,
        target: Balance,
    ): Result<VoucherOffboarding> = runCancellableCatching {
        val converter = coinageBalanceConverterUseCase.create().getOrThrow()
        with(converter) { pickVoucherForOffboardingOrThrow(availableVouchers, target) }
    }

    context(coinageContext: CoinageBalanceConversionContext)
    private suspend fun determinePlan(amount: Balance): ExternalPaymentPlan {
        val availableVouchers = assetSelector.getSelectableVouchers(SpendScope.SPENDABLE)

        if (availableVouchers.totalBalance() >= amount) {
            val offboarding = pickVoucherForOffboardingOrThrow(availableVouchers, target = amount)
            return ExternalPaymentPlan.Ready(offboarding)
        }

        // Vouchers still gaining privacy become spendable on their own, so waiting for them beats spending
        // coins to make up the difference. Nobody is here to confirm a private spend, so they are not spent.
        val activeVouchers = availableVouchers + assetSelector.getVouchersGainingPrivacy()

        if (activeVouchers.totalBalance() >= amount) {
            return ExternalPaymentPlan.NeedsDelayedRetry(DelayReason.VOUCHERS_NOT_READY)
        }

        val deficit = amount - activeVouchers.totalBalance()
        val activeCoins = assetSelector.getSelectableCoins(SpendScope.SPENDABLE)

        if (activeCoins.totalBalance() >= deficit) {
            val coinsToLoad = pickCoinsForDeficit(activeCoins, deficit)
            return ExternalPaymentPlan.LoadCoins(coinsToLoad)
        }

        return ExternalPaymentPlan.NotEnoughAmount(
            activeVouchers = activeVouchers.totalBalance(),
            activeCoins = activeCoins.totalBalance(),
            deficitToCoverWithCoins = deficit,
        )
    }

    context(coinageContext: CoinageBalanceConversionContext)
    private fun pickVoucherForOffboardingOrThrow(
        vouchers: List<RecyclerVoucher>,
        target: Balance,
    ): VoucherOffboarding {
        require(vouchers.totalBalance() >= target) {
            "Insufficient vouchers balance ${vouchers.totalBalance()} to cover target $target"
        }

        val sorted = vouchers.sortedByDescending { coinageContext.formatExponentToBalance(it.recyclerValue) }

        val selected = mutableListOf<RecyclerVoucher>()
        var accumulated = Balance.ZERO

        for (voucher in sorted) {
            if (accumulated >= target) break
            selected.add(voucher)
            accumulated += coinageContext.formatExponentToBalance(voucher.recyclerValue)
        }

        val surplus = (accumulated - target)

        return VoucherOffboarding(selected, surplus)
    }

    context(coinageContext: CoinageBalanceConversionContext)
    private fun pickCoinsForDeficit(
        coins: List<Coin>,
        deficitPlanks: Balance,
    ): List<Coin> {
        val sorted = coins.sortedByDescending { coinageContext.formatExponentToBalance(it.valueExponent) }

        val selected = mutableListOf<Coin>()
        var accumulated = Balance.ZERO

        for (coin in sorted) {
            if (accumulated >= deficitPlanks) break
            selected.add(coin)
            accumulated += coinageContext.formatExponentToBalance(coin.valueExponent)
        }

        return selected
    }
}
