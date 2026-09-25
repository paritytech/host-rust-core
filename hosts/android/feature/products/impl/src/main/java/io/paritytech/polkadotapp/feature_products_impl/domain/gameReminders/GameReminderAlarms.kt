package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

/** The OS alarm behind each product's reminder; a product holds at most one, so arming replaces it. */
interface GameReminderAlarms {
    fun arm(productId: String, fireAtMs: Long)

    fun disarm(productId: String)
}
