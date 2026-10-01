package io.paritytech.polkadotapp.feature_videogame_impl.presentation.autoLaunch

import io.paritytech.polkadotapp.common.data.app.AppLifecycleState
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.ProductGameSlot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.RealProductGameReminder
import io.paritytech.polkadotapp.test_shared.FakeTimeProvider
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify

@OptIn(ExperimentalCoroutinesApi::class)
class ProductGameAutoOpenerTest {
    private val reminder: RealProductGameReminder = mock()
    private val router: VideoGameRouter = mock()
    private val lifecycle: AppLifecycleObserver = mock()
    private val lifecycleState = MutableStateFlow(AppLifecycleState.FOREGROUND)

    private val game = ProductId.fromStoredValue("game.dot")
    private val other = ProductId.fromStoredValue("acme.dot")
    private val slot = ProductGameSlot(game.value, startsAtMillis = 60_000, ringAlarm = true)
    private val laterSlot = ProductGameSlot(other.value, startsAtMillis = 120_000, ringAlarm = true)

    @Test
    fun `opens the soonest product at its start while in the foreground and drops its slot`() = runTest {
        startOpener(laterSlot, slot)

        advanceTimeBy(59_999)
        runCurrent()
        verify(router, never()).openGameProduct(game)

        advanceTimeBy(1)
        runCurrent()
        verify(router).openGameProduct(game)
        verify(reminder).clear(slot)
        verify(router, never()).openGameProduct(other)
    }

    @Test
    fun `opens a slot whose start passed within the grace`() = runTest {
        advanceTimeBy(slot.startsAtMillis + 29_999)

        startOpener(slot)

        verify(router).openGameProduct(game)
    }

    @Test
    fun `does not open a slot whose start passed beyond the grace`() = runTest {
        advanceTimeBy(slot.startsAtMillis + 30_000)

        startOpener(slot)

        verify(router, never()).openGameProduct(game)
    }

    @Test
    fun `leaving the foreground mid-countdown neither opens nor drops the slot`() = runTest {
        startOpener(slot)

        advanceTimeBy(30_000)
        lifecycleState.value = AppLifecycleState.BACKGROUND
        runCurrent()
        advanceTimeBy(31_000)
        runCurrent()

        verify(router, never()).openGameProduct(game)
        verify(reminder, never()).clear(slot)
    }

    private fun TestScope.startOpener(vararg slots: ProductGameSlot) {
        whenever(reminder.slots).thenReturn(MutableStateFlow(slots.toList()))
        whenever(lifecycle.subscribe()).thenReturn(lifecycleState)
        val opener = ProductGameAutoOpener(reminder, lifecycle, router, FakeTimeProvider { testScheduler.currentTime })

        with(ComputationalScope(backgroundScope)) { opener.initialize() }
        runCurrent()
    }
}
