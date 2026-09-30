package io.paritytech.polkadotapp.feature_products_api.domain.game

import io.paritytech.polkadotapp.feature_products_api.model.ProductId

/** Reminds the player of a product's next game start; each product holds one reminder. */
interface ProductGameReminder {
    /**
     * Remind about [productId]'s game starting at [startsAtMillis] (Unix ms), replacing its own reminder.
     * [ringAlarm] asks for an alarm and [addCalendarEvent] for a calendar event.
     */
    suspend fun schedule(productId: ProductId, startsAtMillis: Long, ringAlarm: Boolean, addCalendarEvent: Boolean)

    /** Drop [productId]'s reminder, if any. */
    suspend fun cancel(productId: ProductId)

    /** Re-arm the held reminders after a reboot, dropping those whose start has passed. */
    suspend fun restore()
}
