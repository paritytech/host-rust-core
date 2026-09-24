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
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class E2EPendingChatMessages(private val scope: CoroutineScope) {
    @Inject
    constructor(dispatchers: CoroutineDispatchers) :
        this(CoroutineScope(SupervisorJob() + dispatchers.computation))

    data class PendingMessage(val roomId: String?, val text: String)

    private val pending = ConcurrentHashMap<ProductId, PendingMessage>()
    private val attached = ConcurrentHashMap<ProductId, ProductWorker>()

    fun queue(productId: ProductId, roomId: String?, text: String) {
        if (!BuildConfig.DEBUG) return

        val message = PendingMessage(roomId, text)
        val worker = attached[productId]
        if (worker == null) pending[productId] = message else deliver(productId, worker, message)
    }

    fun attach(productId: ProductId, worker: ProductWorker) {
        attached[productId] = worker
        pending.remove(productId)?.let { deliver(productId, worker, it) }
    }

    fun detach(productId: ProductId, worker: ProductWorker) {
        attached.remove(productId, worker)
    }

    // Delivery waits on the worker's boot, so it never runs in the caller: the receiver is inside goAsync().
    private fun deliver(productId: ProductId, worker: ProductWorker, message: PendingMessage) {
        scope.launch {
            runCatching { worker.onUserMessage(message.roomId, message.text).getOrThrow() }
                .onSuccess { Timber.tag(E2E_LOG_TAG).i(E2EAcks.messageDelivered(productId.value, message.roomId)) }
                .onFailure { error ->
                    if (error is CancellationException) {
                        pending[productId] = message
                        Timber.tag(E2E_LOG_TAG).i(E2EAcks.messageRequeued(productId.value, message.roomId))
                        return@onFailure
                    }
                    Timber.tag(E2E_LOG_TAG)
                        .i(E2EAcks.error("deliver_message", error.message ?: error::class.java.simpleName))
                }
        }
    }
}
