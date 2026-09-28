package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import io.paritytech.polkadotapp.feature_products_api.domain.game.ProductGameReminder
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameNotificationPublisher
import io.paritytech.polkadotapp.feature_videogame_impl.data.notifications.VideoGameSettingsPreferences
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject
import javax.inject.Singleton

data class ProductGameSlot(val productId: ProductId, val startsAtMillis: Long)

/**
 * One slot for the whole host: any product's schedule replaces it, only its holder can cancel it, and it
 * is kept after the start for the notification tap, whose link names no product. Locked because the
 * TrUAPI core calls in from its dispatch pool.
 */
@Singleton
class RealProductGameReminder @Inject constructor(
    private val preferences: VideoGameSettingsPreferences,
    private val scheduler: VideoGameReminderScheduler,
    private val notificationPublisher: VideoGameNotificationPublisher,
) : ProductGameReminder {
    val slot: Flow<ProductGameSlot?> get() = preferences.productGameSlotFlow()

    fun currentSlot(): ProductGameSlot? = preferences.getProductGameSlot()

    @Synchronized
    override fun schedule(productId: ProductId, startsAtMillis: Long) {
        preferences.setProductGameSlot(ProductGameSlot(productId, startsAtMillis))
        notificationPublisher.cancelProductGameStartsSoonNotification()
        scheduler.scheduleProductGameStart(startsAtMillis)
    }

    @Synchronized
    override fun cancel(productId: ProductId) {
        currentSlot()?.takeIf { it.productId == productId }?.let(::clear)
    }

    @Synchronized
    override fun restore() {
        val held = currentSlot() ?: return
        if (held.startsAtMillis <= System.currentTimeMillis()) {
            clear(held)
        } else {
            scheduler.scheduleProductGameStart(held.startsAtMillis)
        }
    }

    /** Drop [slot] if it is still the one held, so a schedule made meanwhile survives. */
    @Synchronized
    fun clear(slot: ProductGameSlot) {
        if (currentSlot() != slot) return
        preferences.setProductGameSlot(null)
        scheduler.cancelProductGameStart()
        notificationPublisher.cancelProductGameStartsSoonNotification()
    }
}
