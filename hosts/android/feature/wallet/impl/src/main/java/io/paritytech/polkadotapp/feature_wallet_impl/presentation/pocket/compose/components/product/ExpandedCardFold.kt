package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.product

import androidx.compose.animation.core.animate
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue

/**
 * How much of the expanded card is folded away above the product.
 *
 * [foldedPx] runs from 0, the card fully shown, to [maxFoldPx], the card entirely out of the way and
 * the product holding every pixel below the top bar.
 */
@Stable
internal class ExpandedCardFoldState(initialFoldPx: Float = 0f) {
    var foldedPx by mutableFloatStateOf(initialFoldPx)
        private set

    var maxFoldPx by mutableFloatStateOf(0f)

    /** [delta] is a drag in screen terms, so dragging up — a negative delta — folds the card away. */
    fun drag(delta: Float) {
        foldedPx = (foldedPx - delta).coerceIn(0f, maxFoldPx)
    }

    /** Where a release from the current position lands. */
    fun settledTarget(): Float = if (foldedPx > maxFoldPx / 2f) maxFoldPx else 0f

    suspend fun settle() {
        val target = settledTarget()
        if (foldedPx == target) return

        animate(initialValue = foldedPx, targetValue = target) { value, _ -> foldedPx = value }
    }

    companion object {
        val Saver: Saver<ExpandedCardFoldState, Float> = Saver(
            save = { it.foldedPx },
            restore = { ExpandedCardFoldState(it) }
        )
    }
}

@Composable
internal fun rememberExpandedCardFoldState(): ExpandedCardFoldState =
    rememberSaveable(saver = ExpandedCardFoldState.Saver) { ExpandedCardFoldState() }
