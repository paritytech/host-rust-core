package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import android.content.Context
import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.common.utils.calendar.CalendarEvent
import io.paritytech.polkadotapp.common.utils.calendar.CalendarEventsMixin
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameNotificationPublisher
import io.paritytech.polkadotapp.feature_videogame_impl.data.notifications.VideoGameSettingsPreferences
import io.paritytech.polkadotapp.test_shared.FakeTimeProvider
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.Mockito.clearInvocations
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import org.mockito.Mockito.verifyNoInteractions
import kotlin.time.Duration
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

class RealProductGameReminderTest {
    private val scheduler: VideoGameReminderScheduler = mock()
    private val publisher: VideoGameNotificationPublisher = mock()
    private val calendar = FakeCalendar()
    private val context: Context = mock<Context>().also {
        whenever(it.getString(anyInt())).thenReturn(TITLE)
    }
    private val reminder = RealProductGameReminder(
        VideoGameSettingsPreferences(MapPreferences()),
        scheduler,
        publisher,
        calendar,
        context,
        FakeTimeProvider { NOW },
    )

    private val game = ProductId.fromStoredValue("game.dot")
    private val other = ProductId.fromStoredValue("acme.dot")

    @Test
    fun `schedule holds the slot, arms its alarm and drops a posted notification`() = runTest {
        reminder.schedule(game, START, true, false)

        assertEquals(ProductGameSlot(game, START, true), reminder.currentSlot())
        verify(scheduler).scheduleProductGameStart(START)
        verify(publisher).cancelProductGameStartsSoonNotification()
        assertTrue(calendar.added.isEmpty())
    }

    @Test
    fun `another product is refused while the held start is ahead`() = runTest {
        reminder.schedule(game, START, true, false)
        clearInvocations(scheduler, publisher)

        assertFalse(reminder.schedule(other, START + 1, true, true))

        assertEquals(ProductGameSlot(game, START, true), reminder.currentSlot())
        verifyNoInteractions(scheduler, publisher)
        assertTrue(calendar.added.isEmpty())
    }

    @Test
    fun `the holder replaces its own slot`() = runTest {
        reminder.schedule(game, START, true, false)

        assertTrue(reminder.schedule(game, START + 1, false, false))

        assertEquals(ProductGameSlot(game, START + 1, false), reminder.currentSlot())
    }

    @Test
    fun `a slot whose start has passed is free for another product`() = runTest {
        reminder.schedule(game, NOW - 1_000, true, false)

        assertTrue(reminder.schedule(other, START, true, false))

        assertEquals(ProductGameSlot(other, START, true), reminder.currentSlot())
    }

    @Test
    fun `adds a calendar event when asked and the start is an hour or more away`() = runTest {
        reminder.schedule(game, START, true, true)

        val (event, alertBefore) = calendar.added.single()
        assertEquals(START, event.timeStart)
        assertEquals(30.minutes, event.duration)
        assertEquals(TITLE, event.title)
        assertEquals(5.minutes, alertBefore)
    }

    @Test
    fun `adds a calendar event exactly an hour ahead but not a millisecond less`() = runTest {
        reminder.schedule(game, NOW + 1.hours.inWholeMilliseconds - 1, true, true)
        assertTrue(calendar.added.isEmpty())

        reminder.schedule(game, NOW + 1.hours.inWholeMilliseconds, true, true)
        assertEquals(1, calendar.added.size)
    }

    @Test
    fun `two quick schedules for the same start add the calendar event once`() = runTest {
        val insert = CompletableDeferred<Unit>()
        calendar.insertGate = insert

        launch { reminder.schedule(game, START, true, true) }
        launch { reminder.schedule(game, START, true, true) }
        testScheduler.runCurrent()
        insert.complete(Unit)
        testScheduler.advanceUntilIdle()

        assertEquals(1, calendar.added.size)
    }

    @Test
    fun `only the holder's cancel drops the slot, its alarm and its notification`() = runTest {
        reminder.schedule(game, START, true, false)

        reminder.cancel(other)
        assertEquals(ProductGameSlot(game, START, true), reminder.currentSlot())
        verify(scheduler, never()).cancelProductGameStart()

        reminder.cancel(game)

        assertNull(reminder.currentSlot())
        verify(scheduler).cancelProductGameStart()
        verify(publisher, times(2)).cancelProductGameStartsSoonNotification()
    }

    @Test
    fun `clear leaves a newer schedule alone`() = runTest {
        reminder.schedule(game, START, true, false)
        val opened = ProductGameSlot(game, START, true)
        reminder.schedule(game, START + 1, true, false)

        reminder.clear(opened)

        assertEquals(ProductGameSlot(game, START + 1, true), reminder.currentSlot())
    }

    @Test
    fun `restore re-arms a slot whose start is ahead`() = runTest {
        reminder.schedule(game, START, true, false)
        clearInvocations(scheduler)

        reminder.restore()

        verify(scheduler).scheduleProductGameStart(START)
        assertEquals(ProductGameSlot(game, START, true), reminder.currentSlot())
    }

    @Test
    fun `a slot is withheld and dropped on restore once the grace after its start has run out`() = runTest {
        reminder.schedule(game, NOW - 29_999, true, false)
        assertEquals(ProductGameSlot(game, NOW - 29_999, true), reminder.slotStartingNow())

        reminder.schedule(game, NOW - 30_000, true, false)
        assertNull(reminder.slotStartingNow())

        reminder.restore()

        assertNull(reminder.currentSlot())
        verify(scheduler).cancelProductGameStart()
    }

    private companion object {
        const val NOW = 1_000_000_000_000L
        val START = NOW + 2.hours.inWholeMilliseconds
        const val TITLE = "Game"
    }
}

private class FakeCalendar : CalendarEventsMixin {
    val added = mutableListOf<Pair<CalendarEvent, Duration>>()

    var insertGate: CompletableDeferred<Unit>? = null

    override fun observeEventAddedToCalendar(event: CalendarEvent): Flow<Boolean> = emptyFlow()

    override suspend fun addEvent(event: CalendarEvent): Result<Unit> = Result.success(Unit)

    override suspend fun addEventIfPermitted(event: CalendarEvent, alertBefore: Duration): Result<Unit> {
        if (added.none { (it, _) -> it.timeStart == event.timeStart && it.title == event.title }) {
            insertGate?.await()
            added += event to alertBefore
        }
        return Result.success(Unit)
    }
}

private class MapPreferences : Preferences by mock(Preferences::class.java) {
    private val values = mutableMapOf<String, String>()

    override fun getString(field: String): String? = values[field]

    override fun putString(field: String, value: String?) {
        if (value == null) values.remove(field) else values[field] = value
    }
}
