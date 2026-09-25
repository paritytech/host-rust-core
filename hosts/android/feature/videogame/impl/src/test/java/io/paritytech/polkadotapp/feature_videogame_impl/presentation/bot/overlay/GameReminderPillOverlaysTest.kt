package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import io.paritytech.polkadotapp.feature_products_api.domain.gameReminders.GameReminderPill
import io.paritytech.polkadotapp.feature_products_api.domain.gameReminders.GameReminderPills
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GameReminderPillOverlaysTest {
    private class FixedPills(shown: List<GameReminderPill>) : GameReminderPills {
        override val pills: Flow<List<GameReminderPill>> = flowOf(shown)

        override fun open(productId: String) = Unit
    }

    @Test
    fun `one overlay per pill, owned by no screen`() = runBlocking<Unit> {
        val pills = FixedPills(listOf(GameReminderPill("a.dot", 1_000), GameReminderPill("b.dot", 2_000)))

        val overlays = GameReminderPillOverlays(pills).overlays.first()

        assertEquals(2, overlays.size)
        assertTrue(overlays.all { it.ownedFragmentClasses.isEmpty() })
    }

    @Test
    fun `no pills gives no overlays`() = runBlocking<Unit> {
        val overlays = GameReminderPillOverlays(FixedPills(emptyList())).overlays.first()

        assertTrue(overlays.isEmpty())
    }

    @Test
    fun `countdown rounds up to whole seconds and stops at zero`() {
        assertEquals(180L, secondsUntil(startsAtMs = 180_000, nowMs = 0))
        assertEquals(1L, secondsUntil(startsAtMs = 1_000, nowMs = 1))
        assertEquals(0L, secondsUntil(startsAtMs = 1_000, nowMs = 1_000))
        assertEquals(0L, secondsUntil(startsAtMs = 1_000, nowMs = 5_000))
    }
}
