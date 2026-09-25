package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.parity.truapi.GameHostBridge
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderCenter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import uniffi.truapi_server.HostRejection

/**
 * Serves one product's game reminder calls. Both run inline on the core's shared dispatch pool, so they only
 * enqueue; one consumer applies them in the order the product made them, so a schedule followed by a cancel
 * never ends up holding the reminder.
 */
class ProductGameHostBridge(
    private val productId: ProductId,
    private val center: GameReminderCenter,
    scope: CoroutineScope,
) : GameHostBridge {
    private val operations = Channel<suspend () -> Unit>(Channel.UNLIMITED)
    private val session = scope.coroutineContext.job

    init {
        session.invokeOnCompletion { operations.close() }
        scope.launch {
            for (operation in operations) operation()
        }
    }

    override fun scheduleReminder(startsAt: ULong) {
        val startsAtMs = startsAt.toLong()
        enqueue { center.schedule(productId.value, startsAtMs) }
    }

    override fun cancelReminder() {
        enqueue { center.cancel(productId.value) }
    }

    private fun enqueue(operation: suspend () -> Unit) {
        // A cancelled scope completes only once its children do, so the channel may still be open.
        if (!session.isActive || operations.trySend(operation).isFailure) {
            throw HostRejection.Rejected("game reminder bridge closed")
        }
    }
}
