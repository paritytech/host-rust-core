package io.paritytech.polkadotapp.feature_videogame_impl.domain.autoLaunch

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

    private val slot = ProductGameSlot(ProductId.fromStoredValue("jollity.dot"), startsAtMillis = 60_000)

    @Test
    fun `opens the product at its start while in the foreground and drops the slot`() = runTest {
        startOpener()

        advanceTimeBy(59_999)
        runCurrent()
        verify(router, never()).openGameProduct(slot.productId)

        advanceTimeBy(1)
        runCurrent()
        verify(router).openGameProduct(slot.productId)
        verify(reminder).clear(slot)
    }

    @Test
    fun `leaving the foreground mid-countdown neither opens nor drops the slot`() = runTest {
        startOpener()

        advanceTimeBy(30_000)
        lifecycleState.value = AppLifecycleState.BACKGROUND
        runCurrent()
        advanceTimeBy(31_000)
        runCurrent()

        verify(router, never()).openGameProduct(slot.productId)
        verify(reminder, never()).clear(slot)
    }

    private fun TestScope.startOpener() {
        whenever(reminder.slot).thenReturn(MutableStateFlow(slot))
        whenever(lifecycle.subscribe()).thenReturn(lifecycleState)
        val opener = ProductGameAutoOpener(reminder, lifecycle, router, FakeTimeProvider { testScheduler.currentTime })

        with(ComputationalScope(backgroundScope)) { opener.initialize() }
        runCurrent()
    }
}
