package io.paritytech.polkadotapp.feature_wallet_impl.domain.model

import io.paritytech.polkadotapp.common.utils.mapToSet
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.CoinageBalanceConversionContext
import io.paritytech.polkadotapp.feature_coinage_api.domain.common.balance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinRecyclingState
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageBalance
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageKeyIndex
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclingVerdicts
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.hops
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.recyclerFungibility
import io.paritytech.polkadotapp.feature_coinage_api.domain.recycling.coinageBalanceOf
import io.paritytech.polkadotapp.feature_coinage_api.domain.usecase.CoinageHoldings

/** What the coinage card renders: the partition of the total, and every item making it up. */
data class CoinageHoldingsInfo(
    val balance: CoinageBalance,
    val holdings: List<CoinageHolding>
)

/** Both halves of what the card shows, from one classification — see [CoinageHoldingsInfo]. */
context(conversion: CoinageBalanceConversionContext)
fun CoinageHoldings.toHoldingsInfo() = CoinageHoldingsInfo(
    balance = coinageBalanceOf(coins, verdicts, vouchers, canSpendWithConfirmation),
    holdings = toRows()
)

context(conversion: CoinageBalanceConversionContext)
private fun CoinageHoldings.toRows(): List<CoinageHolding> {
    val usableVouchers = vouchers.usable.mapToSet { it.ringVrfKeyIndex }

    val coinRows = coins.total.map { coin ->
        CoinageHolding.CoinHolding(
            value = coin.balance(),
            isSpendable = verdicts.allowsSpending(coin.derivationIndex, canSpendWithConfirmation),
            derivationIndex = coin.derivationIndex,
            hops = coin.hops,
            recyclerFungibility = coin.recyclerFungibility
        )
    }

    val voucherRows = vouchers.total.map { voucher ->
        CoinageHolding.VoucherHolding(
            value = voucher.balance(),
            isSpendable = voucher.ringVrfKeyIndex in usableVouchers,
            derivationIndex = voucher.ringVrfKeyIndex,
            recyclerFungibility = voucher.recyclerFungibility,
            maxRecyclerFungibility = voucher.maxRecyclerFungibility
        )
    }

    return (coinRows + voucherRows).sortedForDisplay()
}

/**
 * A coin with no verdict has not been judged yet, so it is not spendable on any terms — the same reading the
 * balance takes. A coin held back for privacy is spendable only where the strategy sells that privacy back.
 */
private fun RecyclingVerdicts.allowsSpending(
    derivationIndex: CoinageKeyIndex,
    canSpendWithConfirmation: Boolean
) = when (this[derivationIndex]) {
    CoinRecyclingState.ALLOW_USE -> true
    CoinRecyclingState.TO_RECYCLE -> canSpendWithConfirmation
    CoinRecyclingState.MUST_RECYCLE, null -> false
}
