package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel
import kotlinx.collections.immutable.ImmutableList

/**
 * One row of the holdings list, already reduced to what the row draws.
 *
 * Bar lengths arrive as fractions of the status column rather than as percentages, because the square-root
 * curve that turns a fungibility into a length is not the row's business — and because the two rows draw
 * their bars from different fields but with identical geometry.
 */
@Immutable
sealed interface CoinageHoldingUiModel {
    /** The item's own value, not its denomination. Rendered without a currency symbol. */
    val value: TokenAmountModel

    @Immutable
    data class CoinRow(
        override val value: TokenAmountModel,
        val isSpendable: Boolean,
        /** Oldest hop first, which is also left-most. */
        val hops: ImmutableList<CoinHopUiModel>,
        /**
         * Where the single block ends, for a coin with no past payments at all. Null when the coin's origin
         * was never observed either, which is what leaves the row with only the unknown pair.
         */
        val blockBarEnd: Float?,
    ) : CoinageHoldingUiModel

    @Immutable
    data class VoucherRow(
        override val value: TokenAmountModel,
        val canUnloadNow: Boolean,
        /** Where the solid bar ends: the anonymity the ring will hold once full. */
        val solidBarEnd: Float,
        /** Where the barber pole ends: the anonymity it holds today. Never below [solidBarEnd]. */
        val barberPoleEnd: Float,
    ) : CoinageHoldingUiModel
}

/** One circle. [dotCount] is how many others moved with the coin, capped at what fits inside the circle. */
@Immutable
data class CoinHopUiModel(val dotCount: Int)
