package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BlockLatencyWindowTest {
    @Test
    fun `no average until an interval is observed`() {
        val window = BlockLatencyWindow(maxSamples = 3)
        assertNull(window.averageIntervalMillis())
        window.recordArrival(1_000)
        assertNull(window.averageIntervalMillis())
    }

    @Test
    fun `averages observed intervals`() {
        val window = BlockLatencyWindow(maxSamples = 5)
        listOf(0L, 2_000L, 4_000L, 6_000L).forEach(window::recordArrival)
        assertEquals(2_000L, window.averageIntervalMillis())
    }

    @Test
    fun `keeps only the most recent samples`() {
        val window = BlockLatencyWindow(maxSamples = 3)
        // intervals: 1000, 2000, 3000, 4000 -> keep last three [2000, 3000, 4000] -> avg 3000
        listOf(0L, 1_000L, 3_000L, 6_000L, 10_000L).forEach(window::recordArrival)
        assertEquals(3_000L, window.averageIntervalMillis())
    }

    @Test
    fun `tracks the last arrival`() {
        val window = BlockLatencyWindow(maxSamples = 3)
        assertNull(window.lastArrivalMillis())
        window.recordArrival(5_000)
        assertEquals(5_000L, window.lastArrivalMillis())
    }
}
