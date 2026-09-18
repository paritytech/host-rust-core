package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.data.app.AppLifecycleState
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.feature_connection_status_api.domain.ChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealth
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealthScore
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainMetricReading
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainGlyph
import io.paritytech.polkadotapp.feature_connection_status_api.presentation.mixin.ChainHealthIndicator
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mockito.Mockito.mock
import java.util.concurrent.atomic.AtomicInteger
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class RealChainHealthMixinTest {
    private val monitor: ChainHealthMonitor = mock(ChainHealthMonitor::class.java)
    private val lifecycle = FakeAppLifecycleObserver()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    private val subscriptions = AtomicInteger()
    private val cancellations = AtomicInteger()

    @After
    fun tearDown() = scope.cancel()

    @Test
    fun `items carry the glyph and indicator of their chain`() = runBlocking<Unit> {
        withMonitorEmitting(health(HUB))
        val mixin = createMixin()

        val item = mixin.awaitModel().chains.single()

        assertEquals(ChainGlyph.AssetHub, item.glyph)
        assertEquals(ChainHealthIndicator.Healthy, item.indicator)
    }

    @Test
    fun `the last block's arrival reaches the item so the view can age it`() = runBlocking<Unit> {
        val landed = Instant.fromEpochMilliseconds(1_700_000_000_000)
        withMonitorEmitting(health(HUB, blockProduction(lastBlockAt = landed)))
        val mixin = createMixin()

        assertEquals(landed, mixin.awaitModel().chains.single().lastBlockAt)
    }

    @Test
    fun `a chain with no block seen yet carries no arrival`() = runBlocking<Unit> {
        withMonitorEmitting(health(HUB, blockProduction(lastBlockAt = null)))
        val mixin = createMixin()

        assertNull(mixin.awaitModel().chains.single().lastBlockAt)
    }

    @Test
    fun `the monitor is observed only while the app is in the foreground`() = runBlocking<Unit> {
        withMonitorEmitting(health(PEOPLE))
        val mixin = createMixin()
        val foregroundModel = mixin.awaitModel()
        assertEquals(1, subscriptions.get())

        lifecycle.state.value = AppLifecycleState.BACKGROUND
        awaitUntil { cancellations.get() == 1 }
        assertEquals(foregroundModel, mixin.model.value)

        lifecycle.state.value = AppLifecycleState.FOREGROUND
        awaitUntil { subscriptions.get() == 2 }
    }

    private fun createMixin() = RealChainHealthMixin(
        scope = ComputationalScope(scope),
        monitor = monitor,
        knownChains = KnownChains(people = PEOPLE, assetHub = HUB, bulletIn = BULLETIN, hydration = null),
        appLifecycleObserver = lifecycle,
    )

    private fun withMonitorEmitting(vararg healths: ChainHealth) {
        val observed = flow {
            subscriptions.incrementAndGet()
            emit(healths.toList())
            awaitCancellation()
        }.onCompletion { cancellations.incrementAndGet() }
        whenever(monitor.observeChainsHealth()).thenReturn(observed)
    }

    private suspend fun RealChainHealthMixin.awaitModel() =
        withTimeout(TIMEOUT) { model.first { it.chains.isNotEmpty() } }

    private suspend fun awaitUntil(condition: () -> Boolean) = withTimeout(TIMEOUT) {
        while (!condition()) delay(POLL_INTERVAL_MS)
    }

    private fun health(chainId: String, vararg readings: ChainMetricReading) = ChainHealth(
        chainId = chainId,
        chainName = chainId,
        connection = ChainConnectionPresentation.Connected,
        expectedBlockTime = 6.seconds,
        readings = readings.toList(),
    )

    private fun blockProduction(lastBlockAt: Instant?) = ChainMetricReading.BlockProduction(
        recentBlocks = 5,
        expectedBlocks = 5,
        requiredBlocks = 5,
        lastBlockAt = lastBlockAt,
        score = ChainHealthScore.Perfect,
    )

    private class FakeAppLifecycleObserver : AppLifecycleObserver {
        val state = MutableStateFlow(AppLifecycleState.FOREGROUND)

        override fun subscribe(): Flow<AppLifecycleState> = state

        override fun getCurrentState(): AppLifecycleState = state.value
    }

    private companion object {
        const val PEOPLE = "people"
        const val HUB = "hub"
        const val BULLETIN = "bulletin"
        const val POLL_INTERVAL_MS = 10L
        val TIMEOUT = 5.seconds
    }
}
