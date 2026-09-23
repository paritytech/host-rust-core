package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket

import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.VoucherBarLayout
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.digitalDollar.holdings.voucherBarLayout
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private const val COLUMN = 300f
private const val MIN_WIDTH = 21f
private const val TOLERANCE = 0.001f

class VoucherBarLayoutTest {
    @Test
    fun `with room to spare both segments keep their nominal lengths`() {
        val layout = layoutOf(solidEnd = 0.2f, poleEnd = 0.6f)

        assertEquals(60f, layout.solidWidth, TOLERANCE)
        assertEquals(120f, layout.poleWidth, TOLERANCE)
    }

    @Test
    fun `the segments always meet without a gap`() {
        val layout = layoutOf(solidEnd = 0.2f, poleEnd = 0.6f)

        assertEquals(180f, layout.totalWidth, TOLERANCE)
    }

    /** Full fungibility draws nothing, which is the most private a voucher gets rather than an empty read. */
    @Test
    fun `both ends at zero give the whole minimum to the solid segment`() {
        val layout = layoutOf(solidEnd = 0f, poleEnd = 0f)

        assertEquals(MIN_WIDTH, layout.solidWidth, TOLERANCE)
        assertEquals(0f, layout.poleWidth, TOLERANCE)
    }

    @Test
    fun `a segment whose share rounds away is allowed to vanish`() {
        val allPole = layoutOf(solidEnd = 0f, poleEnd = 0.5f)
        assertEquals(0f, allPole.solidWidth, TOLERANCE)

        val allSolid = layoutOf(solidEnd = 0.5f, poleEnd = 0.5f)
        assertEquals(0f, allSolid.poleWidth, TOLERANCE)
    }

    /**
     * The reason the floor is applied to the bar and not to either segment: a voucher too short to draw
     * still has to report its split honestly.
     */
    @Test
    fun `a bar below the minimum keeps the ratio of its segments`() {
        val layout = layoutOf(solidEnd = 0.01f, poleEnd = 0.04f)

        assertEquals(MIN_WIDTH, layout.totalWidth, TOLERANCE)
        assertEquals(MIN_WIDTH / 4f, layout.solidWidth, TOLERANCE)
        assertEquals(MIN_WIDTH * 3f / 4f, layout.poleWidth, TOLERANCE)
    }

    @Test
    fun `the bar stays within the column and never shrinks below the minimum`() {
        val steps = 20

        for (solidStep in 0..steps) {
            for (poleStep in solidStep..steps) {
                val solidEnd = solidStep / steps.toFloat()
                val poleEnd = poleStep / steps.toFloat()
                val layout = layoutOf(solidEnd, poleEnd)

                assertTrue("bar below the minimum at $solidEnd/$poleEnd", layout.totalWidth >= MIN_WIDTH - TOLERANCE)
                assertTrue("bar past the column at $solidEnd/$poleEnd", layout.totalWidth <= COLUMN + TOLERANCE)
                assertTrue("negative solid at $solidEnd/$poleEnd", layout.solidWidth >= 0f)
                assertTrue("negative pole at $solidEnd/$poleEnd", layout.poleWidth >= 0f)
            }
        }
    }

    private fun layoutOf(solidEnd: Float, poleEnd: Float): VoucherBarLayout = voucherBarLayout(
        columnWidth = COLUMN,
        minWidth = MIN_WIDTH,
        solidEnd = solidEnd,
        poleEnd = poleEnd
    )
}
