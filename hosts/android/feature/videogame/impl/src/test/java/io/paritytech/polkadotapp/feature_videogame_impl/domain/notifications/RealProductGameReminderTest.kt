package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameNotificationPublisher
import io.paritytech.polkadotapp.feature_videogame_impl.data.notifications.VideoGameSettingsPreferences
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.times
import org.mockito.Mockito.verify

class RealProductGameReminderTest {
    private val scheduler: VideoGameReminderScheduler = mock()
    private val publisher: VideoGameNotificationPublisher = mock()
    private val reminder = RealProductGameReminder(VideoGameSettingsPreferences(MapPreferences()), scheduler, publisher)

    private val game = ProductId.fromStoredValue("jollity.dot")
    private val other = ProductId.fromStoredValue("acme.dot")

    @Test
    fun `schedule holds the slot, arms its alarm and drops a posted notification`() {
        reminder.schedule(game, START)

        assertEquals(ProductGameSlot(game, START), reminder.currentSlot())
        verify(scheduler).scheduleProductGameStart(START)
        verify(publisher).cancelProductGameStartsSoonNotification()
    }

    @Test
    fun `a schedule from another product replaces the slot`() {
        reminder.schedule(game, START)
        reminder.schedule(other, START + 1)

        assertEquals(ProductGameSlot(other, START + 1), reminder.currentSlot())
    }

    @Test
    fun `cancel from a product that does not hold the slot keeps it`() {
        reminder.schedule(game, START)

        reminder.cancel(other)

        assertEquals(ProductGameSlot(game, START), reminder.currentSlot())
        verify(scheduler, never()).cancelProductGameStart()
    }

    @Test
    fun `cancel from the holder drops the slot, its alarm and its notification`() {
        reminder.schedule(game, START)

        reminder.cancel(game)

        assertNull(reminder.currentSlot())
        verify(scheduler).cancelProductGameStart()
        verify(publisher, times(2)).cancelProductGameStartsSoonNotification()
    }

    @Test
    fun `clear leaves a newer schedule alone`() {
        reminder.schedule(game, START)
        val opened = ProductGameSlot(game, START)
        reminder.schedule(game, START + 1)

        reminder.clear(opened)

        assertEquals(ProductGameSlot(game, START + 1), reminder.currentSlot())
    }

    private companion object {
        const val START = 1_900_000_000_000L
    }
}

private class MapPreferences : Preferences by mock(Preferences::class.java) {
    private val values = mutableMapOf<String, String>()

    override fun getString(field: String): String? = values[field]

    override fun putString(field: String, value: String?) {
        if (value == null) values.remove(field) else values[field] = value
    }
}
