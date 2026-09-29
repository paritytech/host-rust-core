package io.paritytech.polkadotapp.feature_products_api.domain.game

import io.paritytech.polkadotapp.feature_products_api.model.ProductId

/**
 * Reminds the player of a product's next game start.
 * Temporary: will be replaced by generic reminder and pill APIs.
 */
interface ProductGameReminder {
    /**
     * Remind about [productId]'s game starting at [startsAtMillis] (Unix ms), replacing its own reminder.
     * [ringAlarm] asks for an alarm and [addCalendarEvent] for a calendar event. Returns false without
     * changes when the host cannot take the reminder now.
     */
    suspend fun schedule(productId: ProductId, startsAtMillis: Long, ringAlarm: Boolean, addCalendarEvent: Boolean): Boolean

    /** Cancel the reminder if [productId] holds it. */
    suspend fun cancel(productId: ProductId)
}
