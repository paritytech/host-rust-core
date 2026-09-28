package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.product

import org.junit.Assert.assertEquals
import org.junit.Test

private const val CARD_HEIGHT = 250f

class ExpandedCardFoldStateTest {
    private val state = ExpandedCardFoldState().apply { maxFoldPx = CARD_HEIGHT }

    @Test
    fun `dragging up folds the card away by the distance dragged`() {
        state.drag(-100f)

        assertEquals(100f, state.foldedPx, 0f)
    }

    // The product below grows by exactly what the card gives up, so a fold past the card's own
    // height would leave the product taller than the space there is.
    @Test
    fun `the card folds no further than its own height`() {
        state.drag(-400f)

        assertEquals(CARD_HEIGHT, state.foldedPx, 0f)
    }

    // The card is the default, so dragging down from it must not pull the product off the bottom.
    @Test
    fun `the card cannot be dragged further open than shown`() {
        state.drag(200f)

        assertEquals(0f, state.foldedPx, 0f)
    }

    @Test
    fun `dragging back down unfolds the card again`() {
        state.drag(-200f)
        state.drag(120f)

        assertEquals(80f, state.foldedPx, 0f)
    }

    /**
     * Released mid-drag the card has to pick a side: left part-folded it would crop the face and
     * leave the product an arbitrary height that neither side designed for.
     */
    @Test
    fun `released past halfway the card settles out of the way`() {
        state.drag(-(CARD_HEIGHT / 2f + 1f))

        assertEquals(CARD_HEIGHT, state.settledTarget(), 0f)
    }

    @Test
    fun `released before halfway the card settles back to shown`() {
        state.drag(-(CARD_HEIGHT / 2f - 1f))

        assertEquals(0f, state.settledTarget(), 0f)
    }
}
