package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import io.paritytech.polkadotapp.common.data.time.TimeProvider
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
import kotlin.time.Duration.Companion.seconds

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
    private val calendar: ProductGameCalendar,
    private val timeProvider: TimeProvider,
) : ProductGameReminder {
    private val lock = Mutex()

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
        val leadMillis = startsAtMillis - now()
        lock.withLock { hold(ProductGameSlot(productId.value, startsAtMillis, ringAlarm)) }
        // Outside the slot lock, so a cancel never waits on the calendar provider.
        if (addCalendarEvent && leadMillis >= CALENDAR_MIN_LEAD.inWholeMilliseconds) {
            calendar.addGame(startsAtMillis)
        }
    }

    override suspend fun cancel(productId: ProductId) {
        lock.withLock { currentSlot(productId)?.let(::drop) }
    }

    override suspend fun restore() {
        lock.withLock {
            val now = now()
            val (stale, live) = currentSlots().partition { !it.isLiveAt(now) }
            stale.forEach(::drop)
            live.forEach { scheduler.scheduleProductGameStart(it.product(), it.startsAtMillis) }
        }
    }

    // Only drops [slot] if still held, so a schedule made meanwhile survives.
    suspend fun clear(slot: ProductGameSlot) {
        lock.withLock { drop(slot) }
    }

    private fun hold(slot: ProductGameSlot) {
        store(currentSlots().filterNot { it.productId == slot.productId } + slot)
        notificationPublisher.cancelProductGameStartsSoonNotification(slot.product())
        scheduler.scheduleProductGameStart(slot.product(), slot.startsAtMillis)
    }

    private fun drop(slot: ProductGameSlot) {
        val slots = currentSlots()
        if (slot !in slots) return
        store(slots - slot)
        scheduler.cancelProductGameStart(slot.product())
        notificationPublisher.cancelProductGameStartsSoonNotification(slot.product())
    }

    private fun store(slots: List<ProductGameSlot>) =
        preferences.setProductGameSlots(slots.sortedBy { it.startsAtMillis })

    private fun now() = timeProvider.now().toEpochMilliseconds()

    private companion object {
        val CALENDAR_MIN_LEAD = 1.hours
    }
}

fun ProductGameSlot.product(): ProductId = ProductId.fromStoredValue(productId)
