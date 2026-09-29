package io.paritytech.polkadotapp.feature_wallet_impl.domain.model

import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.CoinageKeyIndex
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.Hop
import io.paritytech.polkadotapp.feature_coinage_api.domain.model.RecyclerFungibility

/**
 * One line of the holdings list: a coin or a voucher, with what the row needs to draw itself.
 *
 * [isSpendable] is spendability under the *selected strategy*, which is not the same question the summary
 * figures answer. The list says "can I spend this, and where is it"; the figures say "how is my money
 * divided". A voucher gaining privacy and a coin held back for privacy both count against the middle figure
 * yet are drawn differently here, and that is intended.
 */
sealed interface CoinageHolding {
    val value: Balance
    val isSpendable: Boolean

    /** Key index, used only as a stable last tie-break so equal-valued rows keep their order. */
    val derivationIndex: CoinageKeyIndex

    /**
     * Sort rank for rows of equal value: a coin the user can spend, then a voucher, then a coin they cannot.
     * Numeric so adding a class never means touching the comparator.
     */
    val classRank: Int

    data class CoinHolding(
        override val value: Balance,
        override val isSpendable: Boolean,
        override val derivationIndex: CoinageKeyIndex,
        val hops: List<Hop>,
        /** Null when the coin's origin was never observed — see `CoinProvenance`. */
        val recyclerFungibility: RecyclerFungibility?,
    ) : CoinageHolding {
        override val classRank: Int = if (isSpendable) SPENDABLE_COIN_RANK else UNSPENDABLE_COIN_RANK
    }

    data class VoucherHolding(
        override val value: Balance,
        override val isSpendable: Boolean,
        override val derivationIndex: CoinageKeyIndex,
        val recyclerFungibility: RecyclerFungibility,
        /** Null until the voucher's first tick in a ring froze one. */
        val maxRecyclerFungibility: RecyclerFungibility?,
    ) : CoinageHolding {
        override val classRank: Int = VOUCHER_RANK
    }
}

/** Value first and descending; the ranks only decide ties. */
fun List<CoinageHolding>.sortedForDisplay(): List<CoinageHolding> = sortedWith(
    compareByDescending<CoinageHolding> { it.value }
        .thenBy { it.classRank }
        // Rows from two installations can share an item number, so both halves of the key are read.
        .then(DataByteArray.compareByBytes(unsigned = true) { it.derivationIndex.installation.value.value })
        .thenBy { it.derivationIndex.item }
)

private const val SPENDABLE_COIN_RANK = 0
private const val VOUCHER_RANK = 1
private const val UNSPENDABLE_COIN_RANK = 2
