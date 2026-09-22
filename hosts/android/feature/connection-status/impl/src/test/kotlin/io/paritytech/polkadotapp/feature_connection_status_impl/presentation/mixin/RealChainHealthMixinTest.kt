package io.paritytech.polkadotapp.feature_connection_status_impl.presentation.mixin

import io.paritytech.polkadotapp.chains.multiNetwork.KnownChains
import io.paritytech.polkadotapp.common.data.app.AppLifecycleState
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.feature_connection_status_api.domain.ChainHealthMonitor
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainConnectionPresentation
import io.paritytech.polkadotapp.feature_connection_status_api.domain.model.ChainHealth
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
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.onCompletion
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.Mockito.mock
import java.util.concurrent.atomic.AtomicInteger
import kotlin.time.Duration.Companion.seconds

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
        assertEquals(ChainHealthIndicator.Healthy(liveness = null), item.indicator)
    }

    @Test
    fun `the production share and the chain's block time shape the indicator`() = runBlocking<Unit> {
        withMonitorEmitting(health(HUB, blockProduction(produced = 8)))
        val mixin = createMixin()

        val item = mixin.awaitModel().chains.single()

        assertEquals(ChainHealthIndicator.of(share = 0.8f, expectedBlockTime = 6.seconds), item.indicator)
    }

    @Test
    fun `a chain not yet measured is healthy with nothing to print`() = runBlocking<Unit> {
        withMonitorEmitting(health(HUB, blockProduction(produced = null)))
        val mixin = createMixin()

        assertEquals(ChainHealthIndicator.Healthy(liveness = null), mixin.awaitModel().chains.single().indicator)
    }

    @Test
    fun `what a chain showed before stands while it is asked how fast it has been going`() = runBlocking<Unit> {
        val healths = withMonitorSequence()
        val mixin = createMixin()

        healths.emit(listOf(health(HUB, blockProduction(produced = 8))))
        mixin.awaitModel()
        healths.emit(listOf(health(HUB, anchorPending())))
        healths.emit(listOf(health(HUB, anchorPending()), health(PEOPLE, anchorPending())))

        val model = withTimeout(TIMEOUT) { mixin.model.first { it.chains.size == 2 } }

        assertEquals(ChainHealthIndicator.of(share = 0.8f, expectedBlockTime = 6.seconds), model.chains.first().indicator)
        assertEquals(ChainHealthIndicator.Healthy(liveness = null), model.chains.last().indicator)
    }

    @Test
    fun `a chain that was connecting is not held on its way back`() = runBlocking<Unit> {
        val healths = withMonitorSequence()
        val mixin = createMixin()

        healths.emit(listOf(health(HUB, connection = ChainConnectionPresentation.Connecting)))
        mixin.awaitModel()
        healths.emit(listOf(health(HUB, anchorPending())))

        val model = withTimeout(TIMEOUT) { mixin.model.first { it.chains.single().indicator != ChainHealthIndicator.Connecting } }

        assertEquals(ChainHealthIndicator.Healthy(liveness = null), model.chains.single().indicator)
    }

    @Test
    fun `a chain that lost its connection is never held`() = runBlocking<Unit> {
        val healths = withMonitorSequence()
        val mixin = createMixin()

        healths.emit(listOf(health(HUB, blockProduction(produced = 8))))
        mixin.awaitModel()
        healths.emit(listOf(health(HUB, anchorPending(), connection = ChainConnectionPresentation.Offline)))

        val model = withTimeout(TIMEOUT) { mixin.model.first { it.chains.single().indicator == ChainHealthIndicator.Offline } }

        assertEquals(ChainHealthIndicator.Offline, model.chains.single().indicator)
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

    private fun withMonitorSequence(): MutableSharedFlow<List<ChainHealth>> {
        val healths = MutableSharedFlow<List<ChainHealth>>(replay = 1)
        whenever(monitor.observeChainsHealth()).thenReturn(healths)
        return healths
    }

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

    private fun health(
        chainId: String,
        vararg readings: ChainMetricReading,
        connection: ChainConnectionPresentation = ChainConnectionPresentation.Connected,
    ) = ChainHealth(
        chainId = chainId,
        chainName = chainId,
        connection = connection,
        expectedBlockTime = 6.seconds,
        readings = readings.toList(),
    )

    private fun blockProduction(produced: Int?) = ChainMetricReading.BlockProduction(
        producedBlocks = produced,
        expectedBlocks = 10,
        anchorPending = false,
    )

    private fun anchorPending() = ChainMetricReading.BlockProduction(
        producedBlocks = null,
        expectedBlocks = 10,
        anchorPending = true,
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
