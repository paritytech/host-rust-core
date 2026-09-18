package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.probe

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_impl.domain.health.scoring.ChainHealthThresholds
import io.paritytech.polkadotapp.test_shared.FakeTimeProvider
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

@OptIn(ExperimentalCoroutinesApi::class)
class BlockProductionProbeTest {
    @Test
    fun `expects window divided by block time blocks and requires five sixths of them`() = runTest {
        val readings = collectReadings(blockTime = 12.seconds)
        runCurrent()

        assertEquals(2, readings.last().expectedBlocks)
        assertEquals(2, readings.last().requiredBlocks)

        val fine = collectReadings(blockTime = 5.seconds)
        runCurrent()
        assertEquals(6, fine.last().expectedBlocks)
        assertEquals(5, fine.last().requiredBlocks)
    }

    @Test
    fun `reports every expected block until a full window has been observed`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)
        runCurrent()

        assertEquals(5, readings.last().recentBlocks)
        advanceTimeBy(29_000); runCurrent()
        assertEquals(5, readings.last().recentBlocks)
    }

    @Test
    fun `counts the blocks that arrived in the last window once it is full`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)
        repeat(3) { advanceTimeBy(6_000); heads.emit(it) }
        advanceTimeBy(19_000); runCurrent()

        assertEquals(3, readings.last().recentBlocks)
        assertEquals(60, readings.last().score.value)
    }

    @Test
    fun `a stall decays to zero as blocks age out`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)
        repeat(5) { advanceTimeBy(6_000); heads.emit(it) }
        runCurrent()
        assertEquals(5, readings.last().recentBlocks)

        advanceTimeBy(37_000); runCurrent()
        assertEquals(0, readings.last().recentBlocks)
        assertEquals(0, readings.last().score.value)
    }

    @Test
    fun `a block arriving late by less than a block time does not lower the count`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)
        listOf(0L, 6_000L, 12_000L, 18_000L, 24_000L, 31_500L, 37_500L, 43_500L).forEachIndexed { index, atMillis ->
            advanceTimeBy(atMillis - testScheduler.currentTime); heads.emit(index)
        }
        advanceTimeBy(500); runCurrent()

        assertEquals(5, readings.filter { testScheduler.currentTime >= 30_000 }.minOf { it.recentBlocks })
    }

    @Test
    fun `more blocks than expected are capped`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)
        repeat(8) { advanceTimeBy(3_000); heads.emit(it) }
        advanceTimeBy(13_000); runCurrent()

        assertEquals(5, readings.last().recentBlocks)
    }

    @Test
    fun `a reconnect restarts the window instead of reading the gap as a stall`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)
        repeat(6) { advanceTimeBy(6_000); heads.emit(it) }
        connection.value = ChainConnectionPresentation.Connecting
        advanceTimeBy(20_000); runCurrent()
        assertEquals(3, readings.last().recentBlocks)

        connection.value = ChainConnectionPresentation.Connected
        runCurrent()
        assertEquals(5, readings.last().recentBlocks)
        advanceTimeBy(29_000); runCurrent()
        assertEquals(5, readings.last().recentBlocks)
    }

    @Test
    fun `the observed gap leaves the outage line where the configured block time put it`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)

        advanceTimeBy(31_000); runCurrent()
        repeat(4) { index ->
            heads.emit(index)
            advanceTimeBy(2_000); runCurrent()
        }

        // 30s / 6s configured, not 30s / the 2s actually seen.
        assertEquals(5, readings.last().expectedBlocks)
    }

    @Test
    fun `reports when the last block landed`() = runTest {
        val readings = collectReadings(blockTime = 6.seconds)

        advanceTimeBy(10_000); runCurrent()
        heads.emit(1)
        runCurrent()
        val landed = testScheduler.currentTime

        advanceTimeBy(5_000); runCurrent()

        assertEquals(Instant.fromEpochMilliseconds(landed), readings.last().lastBlockAt)
    }

    private lateinit var heads: MutableSharedFlow<Int>
    private lateinit var connection: MutableStateFlow<ChainConnectionPresentation>

    private fun sampleTicks(): Flow<Unit> = flow {
        while (true) {
            emit(Unit)
            delay(ChainHealthThresholds.SAMPLE_TICK)
        }
    }

    private fun TestScope.collectReadings(blockTime: Duration): List<ChainMetricReading.BlockProduction> {
        heads = MutableSharedFlow(extraBufferCapacity = 64)
        connection = MutableStateFlow(ChainConnectionPresentation.Connected)
        val probe = BlockProductionProbe(FakeTimeProvider { testScheduler.currentTime })
        val context = ChainMetricContext(
            bestBlockNumber = heads,
            expectedBlockTime = blockTime,
            pendingRequests = emptyFlow(),
            connection = connection,
            ticks = sampleTicks(),
        )
        val results = mutableListOf<ChainMetricReading.BlockProduction>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            probe.observe(context).collect { results += it as ChainMetricReading.BlockProduction }
        }
        return results
    }
}
