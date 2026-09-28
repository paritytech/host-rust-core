package io.paritytech.polkadotapp.feature_products_api.domain.game

import io.paritytech.polkadotapp.feature_products_api.model.ProductId

/** Holds a product's next game start so the host can remind the player and open the product then. */
interface ProductGameReminder {
    /** Remind about [productId]'s game starting at [startsAtMillis] (Unix ms), replacing any held reminder. */
    fun schedule(productId: ProductId, startsAtMillis: Long)

    /** Cancel the reminder if [productId] holds it. */
    fun cancel(productId: ProductId)

    /** Re-arm the held reminder after a reboot, dropping it once its start has passed. */
    fun restore()
}
