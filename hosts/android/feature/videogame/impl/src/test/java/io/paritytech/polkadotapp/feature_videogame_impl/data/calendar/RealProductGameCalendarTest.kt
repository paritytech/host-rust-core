package io.paritytech.polkadotapp.feature_videogame_impl.data.calendar

import android.content.Context
import io.paritytech.polkadotapp.common.utils.calendar.CalendarEvent
import io.paritytech.polkadotapp.common.utils.calendar.CalendarEventsMixin
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.mockito.ArgumentMatchers.anyInt
import org.mockito.ArgumentMatchers.anyString
import org.mockito.Mockito.mock
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes

class RealProductGameCalendarTest {
    private val mixin = FakeCalendarEventsMixin()
    private val context: Context = mock<Context>().also {
        whenever(it.getString(anyInt(), anyString())).thenReturn(TITLE)
    }
    private val calendar = RealProductGameCalendar(mixin, context)

    @Test
    fun `adds a titled half-hour event with an alert five minutes before`() = runTest {
        calendar.addGame(START)

        val (event, alertBefore) = mixin.added.single()
        assertEquals(START, event.timeStart)
        assertEquals(30.minutes, event.duration)
        assertEquals(TITLE, event.title)
        assertEquals(5.minutes, alertBefore)
    }

    @Test
    fun `two quick adds for the same start add the event once`() = runTest {
        val insert = CompletableDeferred<Unit>()
        mixin.insertGate = insert

        launch { calendar.addGame(START) }
        launch { calendar.addGame(START) }
        testScheduler.runCurrent()
        insert.complete(Unit)
        testScheduler.advanceUntilIdle()

        assertEquals(1, mixin.added.size)
    }

    private companion object {
        const val START = 1_000_000_000_000L
        const val TITLE = "Game"
    }
}

private class FakeCalendarEventsMixin : CalendarEventsMixin {
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
