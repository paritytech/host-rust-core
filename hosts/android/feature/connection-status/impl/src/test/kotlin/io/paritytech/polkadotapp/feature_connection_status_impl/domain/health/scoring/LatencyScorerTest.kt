package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import org.junit.Assert.assertEquals
import org.junit.Test

class LatencyScorerTest {
    private val scorer = LatencyScorer()
    private val ideal = 3_000L
    private val outage = 20_000L

    @Test
    fun `full score within the ideal`() {
        assertEquals(ChainHealthScore.MAX_VALUE, scorer.score(0, ideal, outage).value)
        assertEquals(ChainHealthScore.MAX_VALUE, scorer.score(3_000, ideal, outage).value)
    }

    @Test
    fun `zero score at or beyond the outage`() {
        assertEquals(ChainHealthScore.MIN_VALUE, scorer.score(20_000, ideal, outage).value)
        assertEquals(ChainHealthScore.MIN_VALUE, scorer.score(45_000, ideal, outage).value)
    }

    @Test
    fun `linearly interpolates between ideal and outage`() {
        // midpoint of [3s, 20s] is 11.5s -> 50
        assertEquals(50, scorer.score(11_500, ideal, outage).value)
    }
}
