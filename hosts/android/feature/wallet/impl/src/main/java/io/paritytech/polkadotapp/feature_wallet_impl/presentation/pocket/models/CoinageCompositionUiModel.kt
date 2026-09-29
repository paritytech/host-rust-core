package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.models

import androidx.compose.runtime.Immutable

/**
 * The composition bar's two segments, as value-weighted shares of the total.
 *
 * A direct picture of the two figures printed below it — the same buckets in the same order — which is why
 * the bar needs no legend of its own beyond the swatches that share its fills.
 */
@Immutable
data class CoinageCompositionUiModel(
    val readyFraction: Float,
    val clearingFraction: Float,
) {
    /** Nothing held: the bar renders as a bare capsule frame. */
    val isEmpty: Boolean = readyFraction == 0f && clearingFraction == 0f

    companion object {
        val EMPTY = CoinageCompositionUiModel(0f, 0f)
    }
}
