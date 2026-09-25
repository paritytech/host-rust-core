package io.paritytech.polkadotapp.feature_products_api.domain.gameReminders

import kotlinx.coroutines.flow.Flow

/** A product whose game starts within the next three minutes, while that product is not on screen. */
data class GameReminderPill(
    val productId: String,
    val startsAtMs: Long,
)

/** The "Game starts in" countdown pills the host shows for product games. */
interface GameReminderPills {
    /** One pill per product in its last three minutes before the start, hidden while its SPA is on screen. */
    val pills: Flow<List<GameReminderPill>>

    /** Opens the product behind a tapped pill. Must be called on the main thread. */
    fun open(productId: String)
}
