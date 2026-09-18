package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket

import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.coinMarkLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

private const val DISC = 21f
private const val GAP = 4f
private const val CHIP = 26f

class CoinMarkLayoutTest {
    @Test
    fun `hops that all fit are all drawn without a chip`() {
        val layout = layoutOf(columnWidth = 300f, hopCount = 4)

        assertEquals(4, layout.discCount)
        assertFalse(layout.showChip)
        assertEquals(0, layout.hiddenHops)
    }

    @Test
    fun `a run that exactly fills the column needs no chip`() {
        // four discs and three gaps
        val layout = layoutOf(columnWidth = 4 * DISC + 3 * GAP, hopCount = 4)

        assertEquals(4, layout.discCount)
        assertFalse(layout.showChip)
    }

    /**
     * A disc gives up its place, and keeps giving it up until the chip actually fits — a chip is wider than
     * the disc it replaces, so freeing exactly one slot is not always enough. Here four discs fit, but three
     * would leave only 21pt where the chip needs 26, so it settles at two.
     */
    @Test
    fun `an overflowing run frees as many disc slots as the chip needs`() {
        val layout = layoutOf(columnWidth = 4 * DISC + 3 * GAP, hopCount = 9)

        assertEquals(2, layout.discCount)
        assertTrue(layout.showChip)
        assertEquals(7, layout.hiddenHops)
    }

    /** Every hop is accounted for: what is drawn plus what the chip counts is the whole history. */
    @Test
    fun `no hop is ever silently dropped`() {
        for (column in 20..320 step 7) {
            for (hops in 1..12) {
                val layout = layoutOf(column.toFloat(), hops)
                val accounted = layout.discCount + layout.hiddenHops

                assertEquals("column=$column hops=$hops", hops, accounted)
            }
        }
    }

    @Test
    fun `a column too narrow for the chip shows no marks at all`() {
        val layout = layoutOf(columnWidth = DISC, hopCount = 5)

        assertEquals(0, layout.discCount)
        assertFalse(layout.showChip)
        assertEquals(5, layout.hiddenHops)
    }

    @Test
    fun `a chip is only ever drawn with room for it`() {
        for (column in 20..320 step 3) {
            val layout = layoutOf(column.toFloat(), hopCount = 20)
            if (layout.showChip) {
                val used = layout.discCount * (DISC + GAP)
                assertTrue("column=$column", column - used >= CHIP)
            }
        }
    }

    private fun layoutOf(columnWidth: Float, hopCount: Int) = coinMarkLayout(
        columnWidth = columnWidth,
        discDiameter = DISC,
        gap = GAP,
        chipMinWidth = CHIP,
        hopCount = hopCount
    )
}
