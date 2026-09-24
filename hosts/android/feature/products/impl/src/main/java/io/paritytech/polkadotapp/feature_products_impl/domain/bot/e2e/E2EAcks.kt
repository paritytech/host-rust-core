package io.paritytech.polkadotapp.feature_products_impl.domain.bot.e2e

const val E2E_LOG_TAG = "truapi.e2e"

object E2EAcks {
    const val SEED_IDENTITY_DONE = "seed_identity done"

    fun productRegistered(productId: String) = "product registered id=$productId"

    fun messageQueued(productId: String, roomId: String?) = "message queued ${target(productId, roomId)}"

    fun messageDelivered(productId: String, roomId: String?) = "message delivered ${target(productId, roomId)}"

    fun messageRequeued(productId: String, roomId: String?) =
        "message requeued ${target(productId, roomId)} (worker restarting)"

    fun customRendererUpdate(productId: String) = "custom_renderer_update product=$productId"

    fun error(hook: String, reason: String) = "error $hook $reason"

    private fun target(productId: String, roomId: String?) = "product=$productId room=${roomId ?: NO_ROOM}"

    private const val NO_ROOM = "-"
}
