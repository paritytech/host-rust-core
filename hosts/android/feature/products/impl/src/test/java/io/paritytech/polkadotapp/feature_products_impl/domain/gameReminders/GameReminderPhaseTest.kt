package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class GameReminderPhaseTest {
    private val reminder = gameReminder()

    @Test
    fun `phase is pending more than three minutes before the start`() {
        assertPhaseAt(untilStartMs = 180_001, GameReminderPhase.PENDING)
    }

    @Test
    fun `phase is imminent from three minutes before the start`() {
        assertPhaseAt(untilStartMs = 180_000, GameReminderPhase.IMMINENT)
        assertPhaseAt(untilStartMs = 1, GameReminderPhase.IMMINENT)
    }

    @Test
    fun `phase is started from the start until just before the hour ends`() {
        assertPhaseAt(untilStartMs = 0, GameReminderPhase.STARTED)
        assertPhaseAt(untilStartMs = -3_599_999, GameReminderPhase.STARTED)
    }

    @Test
    fun `phase is expired once the hour after the start has passed`() {
        assertPhaseAt(untilStartMs = -3_600_000, GameReminderPhase.EXPIRED)
    }

    @Test
    fun `next boundary walks pill then start then the end of the hour`() {
        val pill = GAME_START_MS - GameReminderTiming.PILL_LEAD_MS
        val end = GAME_START_MS + GameReminderTiming.OPEN_WINDOW_MS

        assertEquals(pill, nextGameReminderBoundary(pill - 1, listOf(reminder)))
        assertEquals(GAME_START_MS, nextGameReminderBoundary(pill, listOf(reminder)))
        assertEquals(end, nextGameReminderBoundary(GAME_START_MS, listOf(reminder)))
        assertNull(nextGameReminderBoundary(end, listOf(reminder)))
    }

    @Test
    fun `next boundary picks the earliest across products`() {
        val later = gameReminder(productId = "later.dot", startsAtMs = GAME_START_MS + 60_000)

        val next = nextGameReminderBoundary(GAME_START_MS - 1, listOf(later, reminder))

        assertEquals(GAME_START_MS, next)
    }

    private fun assertPhaseAt(untilStartMs: Long, expected: GameReminderPhase) {
        assertEquals(expected, GameReminderPhase.of(reminder, GAME_START_MS - untilStartMs))
    }
}
