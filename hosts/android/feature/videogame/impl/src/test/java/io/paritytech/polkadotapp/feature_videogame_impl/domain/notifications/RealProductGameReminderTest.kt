package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameNotificationPublisher
import io.paritytech.polkadotapp.feature_videogame_impl.data.notifications.VideoGameSettingsPreferences
import io.paritytech.polkadotapp.test_shared.FakeTimeProvider
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.Mockito.clearInvocations
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify
import kotlin.time.Duration.Companion.hours

class RealProductGameReminderTest {
    private val scheduler: VideoGameReminderScheduler = mock()
    private val publisher: VideoGameNotificationPublisher = mock()
    private val calendar = RecordingCalendar()
    private val osAccess = FakeOsAccess()
    private val reminder = RealProductGameReminder(
        VideoGameSettingsPreferences(MapPreferences()),
        scheduler,
        publisher,
        calendar,
        osAccess,
        FakeTimeProvider { NOW },
    )

    private val game = ProductId.fromStoredValue("game.dot")
    private val other = ProductId.fromStoredValue("acme.dot")

    @Test
    fun `schedule holds the slot, arms its alarm and drops a posted notification`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)

        val result = reminder.schedule(game, START)

        assertSuccess(result)
        assertEquals(listOf(ProductGameSlot(game.value, START, true)), reminder.currentSlots())
        verify(scheduler).scheduleProductGameStart(game, START)
        verify(publisher).cancelProductGameStartsSoonNotification(game)
        assertTrue(calendar.added.isEmpty())
    }

    @Test
    fun `holds the slot without an alarm when exact alarms are refused`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = false, calendar = false)

        val result = reminder.schedule(game, START)

        assertSuccess(result)
        assertEquals(listOf(ProductGameSlot(game.value, START, false)), reminder.currentSlots())
    }

    @Test
    fun `fails and holds nothing when notifications are refused`() = runTest {
        withOsAllowing(notifications = false, exactAlarms = true, calendar = true)

        val result = reminder.schedule(game, START)

        assertTrue(result.isFailure)
        assertTrue(reminder.currentSlots().isEmpty())
        assertEquals(listOf(OsAsk.Notifications), osAccess.asked)
        verify(scheduler, never()).scheduleProductGameStart(game, START)
        assertTrue(calendar.added.isEmpty())
    }

    @Test
    fun `each product holds its own slot, soonest first`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        reminder.schedule(game, START + 1)
        withOsAllowing(notifications = true, exactAlarms = false, calendar = false)
        reminder.schedule(other, START)

        assertEquals(
            listOf(ProductGameSlot(other.value, START, false), ProductGameSlot(game.value, START + 1, true)),
            reminder.currentSlots(),
        )
        verify(scheduler).scheduleProductGameStart(game, START + 1)
        verify(scheduler).scheduleProductGameStart(other, START)
    }

    @Test
    fun `a product replaces its own slot`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        reminder.schedule(game, START)
        withOsAllowing(notifications = true, exactAlarms = false, calendar = false)

        reminder.schedule(game, START + 1)

        assertEquals(listOf(ProductGameSlot(game.value, START + 1, false)), reminder.currentSlots())
    }

    @Test
    fun `asks for calendar access and adds an event when the start is an hour or more away`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = true)

        reminder.schedule(game, START)

        assertEquals(listOf(OsAsk.Notifications, OsAsk.ExactAlarms, OsAsk.Calendar), osAccess.asked)
        assertEquals(listOf(START), calendar.added)
    }

    @Test
    fun `adds no event when calendar access is refused`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)

        val result = reminder.schedule(game, START)

        assertSuccess(result)
        assertTrue(calendar.added.isEmpty())
    }

    @Test
    fun `neither asks for calendar access nor adds an event a millisecond under an hour ahead`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = true)

        reminder.schedule(game, NOW + 1.hours.inWholeMilliseconds - 1)

        assertEquals(listOf(OsAsk.Notifications, OsAsk.ExactAlarms), osAccess.asked)
        assertTrue(calendar.added.isEmpty())
    }

    @Test
    fun `adds a calendar event exactly an hour ahead`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = true)

        reminder.schedule(game, NOW + 1.hours.inWholeMilliseconds)

        assertEquals(listOf(NOW + 1.hours.inWholeMilliseconds), calendar.added)
    }

    @Test
    fun `a cancel made while a schedule waits on a prompt applies after it`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        val notificationsAnswer = withPendingNotificationsPrompt()

        launch { reminder.schedule(game, START) }
        testScheduler.runCurrent()
        launch { reminder.cancel(game) }
        testScheduler.runCurrent()
        notificationsAnswer.complete(true)
        testScheduler.advanceUntilIdle()

        assertTrue(reminder.currentSlots().isEmpty())
        verify(scheduler).cancelProductGameStart(game)
    }

    @Test
    fun `two schedules apply in call order when the first waits on a prompt`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        val notificationsAnswer = withPendingNotificationsPrompt()

        launch { reminder.schedule(game, START) }
        testScheduler.runCurrent()
        launch { reminder.schedule(game, START + 1) }
        testScheduler.runCurrent()
        notificationsAnswer.complete(true)
        testScheduler.advanceUntilIdle()

        assertEquals(listOf(ProductGameSlot(game.value, START + 1, true)), reminder.currentSlots())
    }

    @Test
    fun `clearing a slot does not wait on a pending prompt`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        reminder.schedule(game, START)
        val notificationsAnswer = withPendingNotificationsPrompt()

        launch { reminder.schedule(other, START) }
        testScheduler.runCurrent()
        reminder.clear(ProductGameSlot(game.value, START, true))

        assertTrue(reminder.currentSlots().isEmpty())
        notificationsAnswer.complete(true)
    }

    @Test
    fun `a cancel drops only that product's slot, alarm and notification`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        reminder.schedule(game, START)
        reminder.schedule(other, START + 1)

        reminder.cancel(other)
        assertEquals(listOf(ProductGameSlot(game.value, START, true)), reminder.currentSlots())
        verify(scheduler).cancelProductGameStart(other)
        verify(publisher, times(2)).cancelProductGameStartsSoonNotification(other)
        verify(scheduler, never()).cancelProductGameStart(game)
        verify(publisher, times(1)).cancelProductGameStartsSoonNotification(game)

        reminder.cancel(game)

        assertTrue(reminder.currentSlots().isEmpty())
        verify(scheduler).cancelProductGameStart(game)
        verify(publisher, times(2)).cancelProductGameStartsSoonNotification(game)
    }

    @Test
    fun `clear leaves a newer schedule alone`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        reminder.schedule(game, START)
        val opened = ProductGameSlot(game.value, START, true)
        reminder.schedule(game, START + 1)

        reminder.clear(opened)

        assertEquals(listOf(ProductGameSlot(game.value, START + 1, true)), reminder.currentSlots())
    }

    @Test
    fun `restore re-arms slots whose start is ahead and drops those past the grace`() = runTest {
        withOsAllowing(notifications = true, exactAlarms = true, calendar = false)
        reminder.schedule(game, START)
        reminder.schedule(other, NOW - 30_000)
        clearInvocations(scheduler)

        reminder.restore()

        verify(scheduler).scheduleProductGameStart(game, START)
        verify(scheduler).cancelProductGameStart(other)
        assertEquals(listOf(ProductGameSlot(game.value, START, true)), reminder.currentSlots())
        assertNull(reminder.currentSlot(other))
    }

    @Test
    fun `a slot stays live until the grace after its start has run out`() = runTest {
        assertTrue(ProductGameSlot(game.value, NOW - 29_999, true).isLiveAt(NOW))
        assertTrue(!ProductGameSlot(game.value, NOW - 30_000, true).isLiveAt(NOW))
    }

    private fun withOsAllowing(notifications: Boolean, exactAlarms: Boolean, calendar: Boolean) {
        osAccess.notifications = notifications
        osAccess.exactAlarms = exactAlarms
        osAccess.calendar = calendar
    }

    private fun withPendingNotificationsPrompt() =
        CompletableDeferred<Boolean>().also { osAccess.pendingNotificationsAnswer = it }

    private fun assertSuccess(result: Result<*>) {
        assertTrue("expected Result.success but was ${result.exceptionOrNull()}", result.isSuccess)
    }

    private companion object {
        const val NOW = 1_000_000_000_000L
        val START = NOW + 2.hours.inWholeMilliseconds
    }
}

private enum class OsAsk { Notifications, ExactAlarms, Calendar }

private class FakeOsAccess : ProductGameOsAccess {
    var notifications = false
    var exactAlarms = false
    var calendar = false

    // Answers only the next notifications ask, once completed.
    var pendingNotificationsAnswer: CompletableDeferred<Boolean>? = null

    val asked = mutableListOf<OsAsk>()

    override suspend fun requestNotifications(): Boolean {
        asked += OsAsk.Notifications
        val pending = pendingNotificationsAnswer ?: return notifications
        pendingNotificationsAnswer = null
        return pending.await()
    }

    override suspend fun requestExactAlarms(): Boolean {
        asked += OsAsk.ExactAlarms
        return exactAlarms
    }

    override suspend fun requestCalendar(): Boolean {
        asked += OsAsk.Calendar
        return calendar
    }
}

private class RecordingCalendar : ProductGameCalendar {
    val added = mutableListOf<Long>()

    override suspend fun addGame(startsAtMillis: Long) {
        added += startsAtMillis
    }
}

private class MapPreferences : Preferences by mock(Preferences::class.java) {
    private val values = mutableMapOf<String, String>()

    override fun getString(field: String): String? = values[field]

    override fun putString(field: String, value: String?) {
        if (value == null) values.remove(field) else values[field] = value
    }
}
