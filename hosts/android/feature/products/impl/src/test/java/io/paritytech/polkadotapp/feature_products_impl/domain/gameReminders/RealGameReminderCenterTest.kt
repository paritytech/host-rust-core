package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.RecordingGameReminderAlarms.Call
import io.paritytech.polkadotapp.test_shared.FakeTimeProvider
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class RealGameReminderCenterTest {
    private val productId = "jollity.dot"
    private val otherProductId = "other.dot"

    private var nowMs = GAME_START_MS - 600_000
    private val alarms = RecordingGameReminderAlarms()

    private fun center(vararg stored: GameReminder): Pair<RealGameReminderCenter, InMemoryGameReminderStore> {
        val store = InMemoryGameReminderStore(stored.toList())
        return RealGameReminderCenter(store, alarms, FakeTimeProvider { nowMs }) to store
    }

    @Test
    fun `schedule arms twenty seconds before the start and persists the reminder`() = runBlocking<Unit> {
        val (center, store) = center()

        center.schedule(productId, GAME_START_MS)

        assertEquals(mapOf(productId to GAME_START_MS - 20_000), alarms.armed)
        assertEquals(mapOf(productId to gameReminder()), store.saved)
        assertEquals(listOf(gameReminder()), center.reminders.value)
    }

    @Test
    fun `reschedule disarms the previous alarm and replaces the reminder`() = runBlocking<Unit> {
        val (center, store) = center()
        val newStart = GAME_START_MS + 60_000

        center.schedule(productId, GAME_START_MS)
        center.schedule(productId, newStart)

        assertEquals(
            listOf(
                Call.Disarm(productId),
                Call.Arm(productId, GAME_START_MS - 20_000),
                Call.Disarm(productId),
                Call.Arm(productId, newStart - 20_000),
            ),
            alarms.calls,
        )
        assertEquals(mapOf(productId to gameReminder(startsAtMs = newStart)), store.saved)
    }

    @Test
    fun `reschedule resets opened after start`() = runBlocking<Unit> {
        nowMs = GAME_START_MS + 1
        val (center, store) = center(gameReminder(openedAfterStart = true))

        center.schedule(productId, GAME_START_MS + 3_600_000)

        assertEquals(false, store.saved.getValue(productId).openedAfterStart)
    }

    @Test
    fun `schedule keeps without arming a start closer than twenty seconds`() = runBlocking<Unit> {
        nowMs = GAME_START_MS - 20_000
        val (center, store) = center()

        center.schedule(productId, GAME_START_MS)

        assertTrue(alarms.armed.isEmpty())
        assertEquals(mapOf(productId to gameReminder()), store.saved)
    }

    @Test
    fun `cancel drops only that product and is idempotent`() = runBlocking<Unit> {
        val (center, store) = center()
        center.schedule(productId, GAME_START_MS)
        center.schedule(otherProductId, GAME_START_MS)

        center.cancel(productId)
        val callsAfterFirstCancel = alarms.calls.size
        center.cancel(productId)

        assertEquals(callsAfterFirstCancel, alarms.calls.size)
        assertEquals(setOf(otherProductId), store.saved.keys)
        assertEquals(setOf(otherProductId), alarms.armed.keys)
        assertEquals(listOf(otherProductId), center.reminders.value.map { it.productId })
    }

    @Test
    fun `mark opened is ignored before the start`() = runBlocking<Unit> {
        nowMs = GAME_START_MS - 1
        val (center, store) = center(gameReminder())

        center.markOpened(productId)

        assertEquals(false, store.saved.getValue(productId).openedAfterStart)
    }

    @Test
    fun `mark opened records a started reminder`() = runBlocking<Unit> {
        nowMs = GAME_START_MS
        val (center, store) = center(gameReminder())

        center.markOpened(productId)

        assertEquals(true, store.saved.getValue(productId).openedAfterStart)
        assertEquals(true, center.reminders.value.single().openedAfterStart)
    }

    @Test
    fun `product left keeps a reminder not opened after the start`() = runBlocking<Unit> {
        nowMs = GAME_START_MS + 1
        val (center, store) = center(gameReminder())

        center.productLeft(productId)

        assertEquals(setOf(productId), store.saved.keys)
        assertTrue(alarms.calls.isEmpty())
    }

    @Test
    fun `product left drops a reminder opened after the start`() = runBlocking<Unit> {
        nowMs = GAME_START_MS + 1
        val (center, store) = center(gameReminder(openedAfterStart = true))

        center.productLeft(productId)

        assertTrue(store.saved.isEmpty())
        assertEquals(listOf(Call.Disarm(productId)), alarms.calls)
        assertTrue(center.reminders.value.isEmpty())
    }

    @Test
    fun `restore drops expired reminders and re-arms future ones`() = runBlocking<Unit> {
        nowMs = GAME_START_MS
        val expired = gameReminder(productId = "expired.dot", startsAtMs = GAME_START_MS - 3_600_000)
        val started = gameReminder(productId = "started.dot", startsAtMs = GAME_START_MS - 1)
        val future = gameReminder(productId = "future.dot", startsAtMs = GAME_START_MS + 600_000)
        val (center, store) = center(expired, started, future)

        center.restoreAll()

        assertEquals(setOf("started.dot", "future.dot"), store.saved.keys)
        assertEquals(mapOf("future.dot" to GAME_START_MS + 580_000), alarms.armed)
        assertTrue(Call.Disarm("expired.dot") in alarms.calls)
        assertEquals(setOf("started.dot", "future.dot"), center.reminders.value.map { it.productId }.toSet())
    }
}
