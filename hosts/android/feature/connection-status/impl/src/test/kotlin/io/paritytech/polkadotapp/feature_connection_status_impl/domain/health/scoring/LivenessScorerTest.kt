package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import org.junit.Assert.assertEquals
import org.junit.Test

class LivenessScorerTest {
    private val scorer = LivenessScorer()
    private val blockTime = 2_000L

    // Derive the expected boundaries from the (tunable) thresholds so the test survives retuning.
    private val plateau = (blockTime * ChainHealthThresholds.LIVENESS_PLATEAU_MULTIPLIER).toLong()
    private val zero = (blockTime * ChainHealthThresholds.LIVENESS_ZERO_MULTIPLIER).toLong()

    @Test
    fun `perfect when nothing observed yet`() {
        assertEquals(
            ChainHealthScore.Perfect,
            scorer.score(blockTime, averageLatencyMillis = null, elapsedSinceLastBlockMillis = null),
        )
    }

    @Test
    fun `full score within the plateau`() {
        assertEquals(ChainHealthScore.MAX_VALUE, scorer.score(blockTime, plateau / 2, 0L).value)
        assertEquals(ChainHealthScore.MAX_VALUE, scorer.score(blockTime, plateau, 0L).value)
    }

    @Test
    fun `zero score at or beyond the zero point`() {
        assertEquals(ChainHealthScore.MIN_VALUE, scorer.score(blockTime, zero, 0L).value)
        assertEquals(ChainHealthScore.MIN_VALUE, scorer.score(blockTime, zero * 2, 0L).value)
    }

    @Test
    fun `linearly interpolates between plateau and zero`() {
        val midpoint = (plateau + zero) / 2
        assertEquals(50, scorer.score(blockTime, midpoint, 0L).value)
    }

    @Test
    fun `takes the worse of average latency and elapsed since last block`() {
        val midpoint = (plateau + zero) / 2
        // healthy average, but a long stall since the last block should still tank the score
        assertEquals(50, scorer.score(blockTime, averageLatencyMillis = plateau / 2, elapsedSinceLastBlockMillis = midpoint).value)
    }
}
