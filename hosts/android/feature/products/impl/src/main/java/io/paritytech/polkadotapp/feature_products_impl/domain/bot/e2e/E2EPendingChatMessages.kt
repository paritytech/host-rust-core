package io.paritytech.polkadotapp.feature_products_impl.domain.bot.e2e

import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.BuildConfig
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorker
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class E2EPendingChatMessages(private val scope: CoroutineScope) {
    @Inject
    constructor(dispatchers: CoroutineDispatchers) :
        this(CoroutineScope(SupervisorJob() + dispatchers.computation))

    data class PendingMessage(val roomId: String?, val text: String)

    // One lock over both maps: parking and draining must not interleave, or a message is lost or doubled.
    private val lock = Any()
    private val pending = mutableMapOf<ProductId, PendingMessage>()
    private val attached = mutableMapOf<ProductId, ProductWorker>()

    fun queue(productId: ProductId, roomId: String?, text: String) {
        if (!BuildConfig.DEBUG) return

        val message = PendingMessage(roomId, text)
        val worker = synchronized(lock) {
            attached[productId].also { if (it == null) pending[productId] = message }
        }
        worker?.let { deliver(productId, it, message) }
    }

    fun attach(productId: ProductId, worker: ProductWorker) {
        val parked = synchronized(lock) {
            attached[productId] = worker
            pending.remove(productId)
        }
        parked?.let { deliver(productId, worker, it) }
    }

    fun detach(productId: ProductId, worker: ProductWorker) {
        synchronized(lock) { if (attached[productId] === worker) attached.remove(productId) }
    }

    // Delivery waits on the worker's boot, so it never runs in the caller: the receiver is inside goAsync().
    private fun deliver(productId: ProductId, worker: ProductWorker, message: PendingMessage) {
        scope.launch {
            runCatching { worker.onUserMessage(message.roomId, message.text).getOrThrow() }
                .onSuccess { Timber.tag(E2E_LOG_TAG).i(E2EAcks.messageDelivered(productId.value, message.roomId)) }
                .onFailure { error ->
                    if (error is CancellationException) {
                        requeue(productId, worker, message)
                        Timber.tag(E2E_LOG_TAG).i(E2EAcks.messageRequeued(productId.value, message.roomId))
                        return@onFailure
                    }
                    Timber.tag(E2E_LOG_TAG)
                        .i(E2EAcks.error("deliver_message", error.message ?: error::class.java.simpleName))
                }
        }
    }

    // A worker that has already been replaced must not park a message the replacement drained past.
    private fun requeue(productId: ProductId, worker: ProductWorker, message: PendingMessage) {
        val replacement = synchronized(lock) {
            val current = attached[productId]
            if (current != null && current !== worker) {
                current
            } else {
                pending[productId] = message
                null
            }
        }
        replacement?.let { deliver(productId, it, message) }
    }
}
