package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderOpenerAction.Left
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderOpenerAction.MarkOpened
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderOpenerAction.Open
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class GameReminderOpenerLogicTest {
    private val productId = "jollity.dot"
    private val afterStart = GAME_START_MS + 1_000

    private val logic = GameReminderOpenerLogic()

    @Test
    fun `a started reminder opens its product once while the app is in the foreground`() {
        val first = logic.handleReminders(listOf(gameReminder()), afterStart)
        val second = logic.handleReminders(listOf(gameReminder()), afterStart)

        assertEquals(listOf(Open(productId)), first + second)
    }

    @Test
    fun `nothing opens before the start`() {
        assertTrue(logic.handleReminders(listOf(gameReminder()), GAME_START_MS - 1_000).isEmpty())
    }

    @Test
    fun `nothing opens while the app is in the background`() {
        logic.handleVisibility(visibleProductId = null, isForeground = false, nowMs = afterStart)

        assertTrue(logic.handleReminders(listOf(gameReminder()), afterStart).isEmpty())
    }

    @Test
    fun `nothing opens once the hour after the start has passed`() {
        assertTrue(logic.handleReminders(listOf(gameReminder()), GAME_START_MS + 3_600_000).isEmpty())
    }

    @Test
    fun `coming back to the foreground within the hour opens the product`() {
        val now = GAME_START_MS + 600_000
        logic.handleVisibility(visibleProductId = null, isForeground = false, nowMs = now)
        val whileAway = logic.handleReminders(listOf(gameReminder()), now)

        val onReturn = logic.handleVisibility(visibleProductId = null, isForeground = true, nowMs = now)

        assertTrue(whileAway.isEmpty())
        assertEquals(listOf(Open(productId)), onReturn)
    }

    @Test
    fun `a reminder already opened after the start is not opened again`() {
        assertTrue(logic.handleReminders(listOf(gameReminder(openedAfterStart = true)), afterStart).isEmpty())
    }

    @Test
    fun `being in the product after the start marks it opened without reopening it`() {
        logic.handleVisibility(visibleProductId = productId, isForeground = true, nowMs = afterStart)

        val actions = logic.handleReminders(listOf(gameReminder()), afterStart)

        assertEquals(listOf(MarkOpened(productId)), actions)
    }

    @Test
    fun `the start passing while in the product marks it opened`() {
        logic.handleVisibility(visibleProductId = productId, isForeground = true, nowMs = GAME_START_MS - 1_000)
        logic.handleReminders(listOf(gameReminder()), GAME_START_MS - 1_000)

        assertEquals(listOf(MarkOpened(productId)), logic.evaluate(GAME_START_MS))
    }

    @Test
    fun `leaving the product after being in it after the start drops the reminder without reopening it`() {
        logic.handleVisibility(visibleProductId = productId, isForeground = true, nowMs = afterStart)
        logic.handleReminders(listOf(gameReminder()), afterStart)

        val actions = logic.handleVisibility(visibleProductId = null, isForeground = true, nowMs = afterStart)

        assertEquals(listOf(Left(productId)), actions)
    }

    @Test
    fun `leaving the product before the start keeps the reminder`() {
        val beforeStart = GAME_START_MS - 60_000
        logic.handleVisibility(visibleProductId = productId, isForeground = true, nowMs = beforeStart)
        logic.handleReminders(listOf(gameReminder()), beforeStart)

        val actions = logic.handleVisibility(visibleProductId = null, isForeground = true, nowMs = beforeStart)

        assertTrue(actions.isEmpty())
    }

    @Test
    fun `a rescheduled reminder opens again at its new start`() {
        val newStart = GAME_START_MS + 3_600_000
        val first = logic.handleReminders(listOf(gameReminder()), afterStart)

        val second = logic.handleReminders(listOf(gameReminder(startsAtMs = newStart)), newStart + 1_000)

        assertEquals(listOf(Open(productId)), first)
        assertEquals(listOf(Open(productId)), second)
    }

    @Test
    fun `a rescheduled reminder is marked opened again when visible after its new start`() {
        val newStart = GAME_START_MS + 3_600_000
        logic.handleVisibility(visibleProductId = productId, isForeground = true, nowMs = afterStart)
        val first = logic.handleReminders(listOf(gameReminder()), afterStart)

        val second = logic.handleReminders(listOf(gameReminder(startsAtMs = newStart)), newStart + 1_000)

        assertEquals(listOf(MarkOpened(productId)), first)
        assertEquals(listOf(MarkOpened(productId)), second)
    }

    @Test
    fun `each started product opens once`() {
        val other = gameReminder(productId = "other.dot")

        val actions = logic.handleReminders(listOf(gameReminder(), other), afterStart)

        assertEquals(listOf(Open(productId), Open("other.dot")), actions)
    }
}
