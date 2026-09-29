package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.common.utils.calendar.CalendarEvent
import io.paritytech.polkadotapp.common.utils.calendar.CalendarEventsMixin
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_products_api.domain.game.ProductGameReminder
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameNotificationPublisher
import io.paritytech.polkadotapp.feature_videogame_impl.data.notifications.VideoGameSettingsPreferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import io.paritytech.polkadotapp.common.R as RCommon

data class ProductGameSlot(val productId: ProductId, val startsAtMillis: Long, val ringAlarm: Boolean)

private val PRODUCT_GAME_START_GRACE = 30.seconds

// Live until the grace after its start has run out.
internal fun ProductGameSlot.isLiveAt(nowMillis: Long) =
    nowMillis - startsAtMillis < PRODUCT_GAME_START_GRACE.inWholeMilliseconds

// One slot for the whole host, kept past its start for the notification tap, whose link names no product.
@Singleton
class RealProductGameReminder @Inject constructor(
    private val preferences: VideoGameSettingsPreferences,
    private val scheduler: VideoGameReminderScheduler,
    private val notificationPublisher: VideoGameNotificationPublisher,
    private val calendarEventsMixin: CalendarEventsMixin,
    @ApplicationContext private val context: Context,
    private val timeProvider: TimeProvider,
) : ProductGameReminder {
    private val lock = Mutex()

    val slot: Flow<ProductGameSlot?> get() = preferences.productGameSlotFlow()

    fun currentSlot(): ProductGameSlot? = preferences.getProductGameSlot()

    fun slotStartingNow(): ProductGameSlot? = currentSlot()?.takeIf { !it.isStale() }

    override suspend fun schedule(
        productId: ProductId,
        startsAtMillis: Long,
        ringAlarm: Boolean,
        addCalendarEvent: Boolean,
    ): Boolean = lock.withLock {
        val now = timeProvider.now().toEpochMilliseconds()
        val held = currentSlot()
        if (held != null && held.productId != productId && held.startsAtMillis > now) return@withLock false

        preferences.setProductGameSlot(ProductGameSlot(productId, startsAtMillis, ringAlarm))
        notificationPublisher.cancelProductGameStartsSoonNotification()
        scheduler.scheduleProductGameStart(startsAtMillis)
        if (addCalendarEvent && startsAtMillis - now >= CALENDAR_MIN_LEAD.inWholeMilliseconds) {
            addCalendarEvent(startsAtMillis)
        }
        true
    }

    override suspend fun cancel(productId: ProductId) {
        lock.withLock { currentSlot()?.takeIf { it.productId == productId }?.let(::drop) }
    }

    suspend fun restore() {
        lock.withLock {
            val held = currentSlot() ?: return
            if (held.isStale()) drop(held) else scheduler.scheduleProductGameStart(held.startsAtMillis)
        }
    }

    // Only drops [slot] if still held, so a schedule made meanwhile survives.
    suspend fun clear(slot: ProductGameSlot) {
        lock.withLock { drop(slot) }
    }

    private fun drop(slot: ProductGameSlot) {
        if (currentSlot() != slot) return
        preferences.setProductGameSlot(null)
        scheduler.cancelProductGameStart()
        notificationPublisher.cancelProductGameStartsSoonNotification()
    }

    private fun ProductGameSlot.isStale() = !isLiveAt(timeProvider.now().toEpochMilliseconds())

    private suspend fun addCalendarEvent(startsAtMillis: Long) {
        val event = CalendarEvent(
            timeStart = startsAtMillis,
            duration = CALENDAR_EVENT_DURATION,
            title = context.getString(RCommon.string.video_game_calendar_event_title),
        )
        calendarEventsMixin.addEventIfPermitted(event, CALENDAR_ALERT_BEFORE).logFailure("product game calendar event")
    }

    private companion object {
        val CALENDAR_MIN_LEAD = 1.hours
        val CALENDAR_EVENT_DURATION = 30.minutes
        val CALENDAR_ALERT_BEFORE = 5.minutes
    }
}
