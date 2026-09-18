package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin.mapper

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealth
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator.Speed
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.time.Duration.Companion.seconds

class ChainHealthIndicatorMapperTest {
    @Test
    fun `disconnected wins over everything`() {
        val health = health(ChainConnectionPresentation.Disconnected, blocks(5, 5), pending(100))

        assertEquals(ChainHealthIndicator.Disconnected, health.toIndicator())
    }

    @Test
    fun `connecting wins over an outage`() {
        val health = health(ChainConnectionPresentation.Connecting, blocks(0, 5))

        assertEquals(ChainHealthIndicator.Connecting, health.toIndicator())
    }

    @Test
    fun `a node that stopped answering is dead even while the socket is connected`() {
        assertEquals(ChainHealthIndicator.Disconnected, connected(blocks(5, 5), pending(0)).toIndicator())
    }

    @Test
    fun `no readings is healthy`() {
        assertEquals(ChainHealthIndicator.Healthy, connected().toIndicator())
    }

    @Test
    fun `five sixths of the expected blocks is the outage line`() {
        assertEquals(ChainHealthIndicator.Healthy, connected(blocks(5, 5)).toIndicator())
        assertEquals(ChainHealthIndicator.Healthy, connected(blocks(5, 6)).toIndicator())
        assertEquals(ChainHealthIndicator.Outage, connected(blocks(4, 5)).toIndicator())
        assertEquals(ChainHealthIndicator.Outage, connected(blocks(0, 5)).toIndicator())
    }

    @Test
    fun `an outage wins over a slow connection`() {
        assertEquals(ChainHealthIndicator.Outage, connected(blocks(3, 5), pending(10)).toIndicator())
    }

    @Test
    fun `connection speed is graded by the worst of pending and response`() {
        assertEquals(ChainHealthIndicator.Healthy, connected(pending(90), response(100)).toIndicator())
        assertSpeed(Speed.Good, connected(pending(100), response(89)).toIndicator())
        assertSpeed(Speed.Good, connected(pending(70)).toIndicator())
        assertSpeed(Speed.Fair, connected(pending(69)).toIndicator())
        assertSpeed(Speed.Fair, connected(pending(40)).toIndicator())
        assertSpeed(Speed.Low, connected(pending(39)).toIndicator())
        assertSpeed(Speed.Low, connected(response(0)).toIndicator())
    }

    @Test
    fun `each band fills its own quarter of the ring end to end`() {
        assertArc(0.75f, connected(pending(89)).toIndicator())
        assertArc(0.5f, connected(pending(70)).toIndicator())
        assertArc(0.5f, connected(pending(69)).toIndicator())
        assertArc(0.25f, connected(pending(40)).toIndicator())
        assertArc(0.25f, connected(pending(39)).toIndicator())
    }

    @Test
    fun `the arc keeps moving inside a band`() {
        val floor = arcOf(connected(pending(70)).toIndicator())
        val middle = arcOf(connected(pending(80)).toIndicator())
        val ceiling = arcOf(connected(pending(89)).toIndicator())

        assertTrue("the arc must grow with the score inside a band", floor < middle && middle < ceiling)
    }

    @Test
    fun `the bottom of the lowest band still draws a stub`() {
        val arc = arcOf(connected(response(0)).toIndicator())

        assertTrue("an empty ring would read as dead rather than slow", arc > 0f)
    }

    @Test
    fun `an outage wins over any speed band`() {
        assertEquals(ChainHealthIndicator.Outage, connected(blocks(3, 5), pending(75)).toIndicator())
    }

    private fun assertSpeed(expected: Speed, indicator: ChainHealthIndicator) {
        val actual = indicator as? ChainHealthIndicator.ConnectionSpeed

        assertEquals(expected, actual?.speed)
    }

    private fun assertArc(expected: Float, indicator: ChainHealthIndicator) {
        val actual = arcOf(indicator)

        assertTrue("expected an arc of $expected but got $actual", abs(expected - actual) < ARC_TOLERANCE)
    }

    private fun arcOf(indicator: ChainHealthIndicator): Float = when (indicator) {
        is ChainHealthIndicator.ConnectionSpeed -> indicator.arc
        else -> throw AssertionError("$indicator carries no arc")
    }

    private fun connected(vararg readings: ChainMetricReading): ChainHealth =
        health(ChainConnectionPresentation.Connected, *readings)

    private fun health(connection: ChainConnectionPresentation, vararg readings: ChainMetricReading): ChainHealth =
        ChainHealth(
            chainId = "people",
            chainName = "People",
            connection = connection,
            expectedBlockTime = 6.seconds,
            readings = readings.toList(),
        )

    private fun blocks(recent: Int, expected: Int): ChainMetricReading = ChainMetricReading.BlockProduction(
        recentBlocks = recent,
        expectedBlocks = expected,
        requiredBlocks = ceil(expected * 5.0 / 6.0).toInt(),
        lastBlockAt = null,
        score = ChainHealthScore.coerced(recent * ChainHealthScore.MAX_VALUE / expected),
    )

    private fun pending(score: Int): ChainMetricReading = ChainMetricReading.PendingRequestLatency(
        latency = 1.seconds,
        target = 1.seconds,
        score = ChainHealthScore.coerced(score),
    )

    private fun response(score: Int): ChainMetricReading = ChainMetricReading.ResponseLatency(
        latency = 1.seconds,
        target = 1.seconds,
        score = ChainHealthScore.coerced(score),
    )

    private companion object {
        const val ARC_TOLERANCE = 0.001f
    }
}
