package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import org.junit.Assert.assertEquals
import org.junit.Test

class FinalityGapScorerTest {
    private val scorer = FinalityGapScorer()
    private val ideal = 6
    private val outage = 24

    @Test
    fun `full score within the plateau`() {
        assertEquals(ChainHealthScore.MAX_VALUE, scorer.score(0, ideal, outage).value)
        assertEquals(ChainHealthScore.MAX_VALUE, scorer.score(6, ideal, outage).value)
    }

    @Test
    fun `zero score at or beyond the zero point`() {
        assertEquals(ChainHealthScore.MIN_VALUE, scorer.score(24, ideal, outage).value)
        assertEquals(ChainHealthScore.MIN_VALUE, scorer.score(100, ideal, outage).value)
    }

    @Test
    fun `linearly interpolates between plateau and zero`() {
        // midpoint of [6, 24] is 15 -> 50
        assertEquals(50, scorer.score(15, ideal, outage).value)
    }

    @Test
    fun `negative gap is treated as healthy`() {
        assertEquals(ChainHealthScore.MAX_VALUE, scorer.score(-3, ideal, outage).value)
    }

    @Test
    fun `honours per-chain thresholds`() {
        // a stricter chain: ideal 2, outage 10 -> midpoint 6 -> 50
        assertEquals(50, scorer.score(6, idealGap = 2, outageGap = 10).value)
    }
}
