package io.paritytech.polkadotapp.feature_connection_status_impl.domain.health

import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.test_shared.FakeTimeProvider
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.time.Duration.Companion.seconds
import kotlin.time.ExperimentalTime

@OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)
class ConnectionSmootherTest {
    private val config = ConnectionSmoothingConfig(
        stabilityWindow = 3.seconds,
        flapWindow = 30.seconds,
        flapDropThreshold = 2,
        flapHold = 10.seconds,
        sustainedDisconnect = 5.seconds,
    )

    @Test
    fun `a first connect settles immediately`() = runTest {
        val results = collectSmoothed()

        source.emit(RawConnectivity.Connected); runCurrent()

        assertEquals(listOf(ChainConnectionPresentation.Connected), results)
    }

    @Test
    fun `a reconnect reports connected only after the stability window`() = runTest {
        val results = collectSmoothed()

        source.emit(RawConnectivity.Connected); runCurrent()
        source.emit(RawConnectivity.Pending); runCurrent()

        source.emit(RawConnectivity.Connected)
        advanceTimeBy(1_000); runCurrent()
        assertEquals(ChainConnectionPresentation.Connecting, results.last())

        advanceTimeBy(2_500); runCurrent() // total 3.5s > 3s
        assertEquals(ChainConnectionPresentation.Connected, results.last())
    }

    @Test
    fun `a reconnect long after its drop aged out still waits out the stability window`() = runTest {
        val results = collectSmoothed()

        source.emit(RawConnectivity.Connected); runCurrent()
        source.emit(RawConnectivity.Pending); runCurrent()
        advanceTimeBy(31_000); runCurrent() // past the 30s flap window, so the drop is purged

        source.emit(RawConnectivity.Connected)
        advanceTimeBy(1_000); runCurrent()
        assertEquals(ChainConnectionPresentation.Connecting, results.last())

        advanceTimeBy(2_500); runCurrent()
        assertEquals(ChainConnectionPresentation.Connected, results.last())
    }

    @Test
    fun `a drop flips to pending immediately`() = runTest {
        val results = collectSmoothed()

        source.emit(RawConnectivity.Connected)
        advanceTimeBy(3_500); runCurrent()
        assertEquals(ChainConnectionPresentation.Connected, results.last())

        source.emit(RawConnectivity.Pending); runCurrent()
        assertEquals(ChainConnectionPresentation.Connecting, results.last())
    }

    @Test
    fun `a settled disconnect reports disconnected only after the cooldown`() = runTest {
        val results = collectSmoothed()

        source.emit(RawConnectivity.Connected)
        advanceTimeBy(3_500); runCurrent()

        source.emit(RawConnectivity.Settled); runCurrent()
        assertEquals(ChainConnectionPresentation.Connecting, results.last())

        advanceTimeBy(5_500); runCurrent()
        assertEquals(ChainConnectionPresentation.Disconnected, results.last())
    }

    @Test
    fun `a settled disconnect repeated faster than the cooldown never reports disconnected`() = runTest {
        val results = collectSmoothed()

        source.emit(RawConnectivity.Connected)
        advanceTimeBy(3_500); runCurrent()

        repeat(10) {
            source.emit(RawConnectivity.Settled); runCurrent()
            advanceTimeBy(1_000); runCurrent()
        }

        assertEquals(ChainConnectionPresentation.Connecting, results.last())
    }

    @Test
    fun `flapping holds pending past the stability window`() = runTest {
        val results = collectSmoothed()

        source.emit(RawConnectivity.Connected)
        advanceTimeBy(3_500); runCurrent()

        // first drop + reconnect: only one drop, so normal stability window applies
        source.emit(RawConnectivity.Pending); runCurrent()
        source.emit(RawConnectivity.Connected)
        advanceTimeBy(3_500); runCurrent()
        assertEquals(ChainConnectionPresentation.Connected, results.last())

        // second drop within the window -> reconnect must wait out the longer flap hold
        source.emit(RawConnectivity.Pending); runCurrent()
        source.emit(RawConnectivity.Connected)
        advanceTimeBy(4_000); runCurrent() // past 3s stability, before 10s flap hold
        assertEquals(ChainConnectionPresentation.Connecting, results.last())

        advanceTimeBy(7_000); runCurrent() // now past the flap hold
        assertEquals(ChainConnectionPresentation.Connected, results.last())
    }

    private lateinit var source: MutableSharedFlow<RawConnectivity>

    private fun TestScope.collectSmoothed(): List<ChainConnectionPresentation> {
        source = MutableSharedFlow(extraBufferCapacity = 64)
        val smoother = ConnectionSmoother(config, FakeTimeProvider { testScheduler.currentTime })
        val results = mutableListOf<ChainConnectionPresentation>()
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            smoother.smooth(source).collect { results += it }
        }
        return results
    }
}
