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
import kotlinx.serialization.Serializable
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import io.paritytech.polkadotapp.common.R as RCommon

@Serializable
data class ProductGameSlot(val productId: String, val startsAtMillis: Long, val ringAlarm: Boolean)

private val PRODUCT_GAME_START_GRACE = 30.seconds

// Live until the grace after its start has run out.
internal fun ProductGameSlot.isLiveAt(nowMillis: Long) =
    nowMillis - startsAtMillis < PRODUCT_GAME_START_GRACE.inWholeMilliseconds

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
    // Serialises the calendar dedupe and insert, apart from the slot lock so a cancel never waits on the provider.
    private val calendarLock = Mutex()

    val slots: Flow<List<ProductGameSlot>> get() = preferences.productGameSlotsFlow()

    fun currentSlots(): List<ProductGameSlot> = preferences.getProductGameSlots()

    fun currentSlot(productId: ProductId): ProductGameSlot? =
        currentSlots().firstOrNull { it.productId == productId.value }

    override suspend fun schedule(
        productId: ProductId,
        startsAtMillis: Long,
        ringAlarm: Boolean,
        addCalendarEvent: Boolean,
    ) {
        val now = timeProvider.now().toEpochMilliseconds()
        val slot = ProductGameSlot(productId.value, startsAtMillis, ringAlarm)
        lock.withLock {
            store(currentSlots().filter { it.productId != productId.value } + slot)
            notificationPublisher.cancelProductGameStartsSoonNotification(productId)
            scheduler.scheduleProductGameStart(productId, startsAtMillis)
        }
        if (addCalendarEvent && startsAtMillis - now >= CALENDAR_MIN_LEAD.inWholeMilliseconds) {
            addCalendarEvent(startsAtMillis)
        }
    }

    override suspend fun cancel(productId: ProductId) {
        lock.withLock { currentSlot(productId)?.let(::drop) }
    }

    override suspend fun restore() {
        lock.withLock {
            for (slot in currentSlots()) {
                if (slot.isStale()) {
                    drop(slot)
                } else {
                    scheduler.scheduleProductGameStart(slot.product(), slot.startsAtMillis)
                }
            }
        }
    }

    // Only drops [slot] if still held, so a schedule made meanwhile survives.
    suspend fun clear(slot: ProductGameSlot) {
        lock.withLock { drop(slot) }
    }

    private fun drop(slot: ProductGameSlot) {
        if (slot !in currentSlots()) return
        store(currentSlots() - slot)
        scheduler.cancelProductGameStart(slot.product())
        notificationPublisher.cancelProductGameStartsSoonNotification(slot.product())
    }

    private fun store(slots: List<ProductGameSlot>) =
        preferences.setProductGameSlots(slots.sortedBy { it.startsAtMillis })

    private fun ProductGameSlot.isStale() = !isLiveAt(timeProvider.now().toEpochMilliseconds())

    private suspend fun addCalendarEvent(startsAtMillis: Long) {
        val event = CalendarEvent(
            timeStart = startsAtMillis,
            duration = CALENDAR_EVENT_DURATION,
            title = context.getString(RCommon.string.video_game_calendar_event_title),
        )
        calendarLock.withLock {
            calendarEventsMixin.addEventIfPermitted(event, CALENDAR_ALERT_BEFORE)
                .logFailure("product game calendar event")
        }
    }

    private companion object {
        val CALENDAR_MIN_LEAD = 1.hours
        val CALENDAR_EVENT_DURATION = 30.minutes
        val CALENDAR_ALERT_BEFORE = 5.minutes
    }
}

fun ProductGameSlot.product(): ProductId = ProductId.fromStoredValue(productId)
