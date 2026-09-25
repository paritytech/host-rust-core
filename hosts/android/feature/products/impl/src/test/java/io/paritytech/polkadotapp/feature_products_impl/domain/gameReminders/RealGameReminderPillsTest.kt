@file:OptIn(ExperimentalCoroutinesApi::class)

package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import io.paritytech.polkadotapp.feature_products_api.domain.gameReminders.GameReminderPill
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import io.paritytech.polkadotapp.test_shared.FakeTimeProvider
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.mock

class RealGameReminderPillsTest {
    private val productId = "jollity.dot"
    private val otherProductId = "other.dot"

    private val visibleProductId = MutableStateFlow<String?>(null)
    private val visibilityTracker: ProductVisibilityTracker = mock()
    private val productsRouter: ProductsRouter = mock()

    private class Harness(val center: RealGameReminderCenter, val emissions: List<List<GameReminderPill>>) {
        val shown: List<GameReminderPill> get() = emissions.last()
    }

    // The clock starts [untilStartMs] before the game and follows the test scheduler's virtual time.
    private fun TestScope.harness(untilStartMs: Long, vararg reminders: GameReminder): Harness {
        whenever(visibilityTracker.visibleProductId).thenReturn(visibleProductId)
        val clock = FakeTimeProvider { GAME_START_MS - untilStartMs + testScheduler.currentTime }
        val center = RealGameReminderCenter(InMemoryGameReminderStore(reminders.toList()), RecordingGameReminderAlarms(), clock)
        val pills = RealGameReminderPills(center, visibilityTracker, clock, productsRouter)
        val emissions = mutableListOf<List<GameReminderPill>>()
        backgroundScope.launch { pills.pills.collect { emissions += it } }
        runCurrent()
        return Harness(center, emissions)
    }

    @Test
    fun `pill is shown from three minutes before the start until the start`() = runTest {
        val harness = harness(untilStartMs = 180_001, gameReminder())
        assertTrue(harness.shown.isEmpty())

        advanceTimeBy(1)
        runCurrent()
        assertEquals(listOf(GameReminderPill(productId, GAME_START_MS)), harness.shown)

        advanceTimeBy(180_000)
        runCurrent()
        assertTrue(harness.shown.isEmpty())
    }

    @Test
    fun `pill is hidden while its product is on screen`() = runTest {
        val harness = harness(untilStartMs = 60_000, gameReminder())

        visibleProductId.value = productId
        runCurrent()
        assertTrue(harness.shown.isEmpty())

        visibleProductId.value = null
        runCurrent()
        assertEquals(listOf(productId), harness.shown.map { it.productId })
    }

    @Test
    fun `each imminent product gets its own pill`() = runTest {
        val harness = harness(
            untilStartMs = 60_000,
            gameReminder(),
            gameReminder(productId = otherProductId, startsAtMs = GAME_START_MS + 30_000),
        )

        assertEquals(listOf(productId, otherProductId), harness.shown.map { it.productId })
    }

    @Test
    fun `cancelling the reminder removes its pill`() = runTest {
        val harness = harness(untilStartMs = 60_000, gameReminder())

        harness.center.cancel(productId)
        runCurrent()

        assertTrue(harness.shown.isEmpty())
    }
}
