package io.paritytech.polkadotapp.feature_products_impl.domain.worker

import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductsBotApi
import io.paritytech.polkadotapp.feature_products_impl.domain.scriptExecutor.HostApiProductsScriptExecutor
import kotlinx.coroutines.CoroutineScope
import timber.log.Timber
import javax.inject.Inject

/**
 * Builds and starts a product's headless worker. Injected into [ProductWorkerRefCounter] once at
 * startup so the ref counter can be exercised without a real runtime, and so the product dependency
 * graph is assembled before any worker boots.
 */
interface WorkerBootFactory {
    /**
     * Boots the worker for [productId] on [scope], wiring [botApi] as its host-call surface.
     * Returns null when the product publishes no worker script (or boot fails): a keep-alive lock
     * on such a product counts but starts nothing.
     */
    suspend fun boot(productId: ProductId, botApi: ProductsBotApi, scope: CoroutineScope): ProductWorker?
}

class RealWorkerBootFactory @Inject constructor(
    private val scriptExecutorFactory: HostApiProductsScriptExecutor.Factory,
) : WorkerBootFactory {
    override suspend fun boot(productId: ProductId, botApi: ProductsBotApi, scope: CoroutineScope): ProductWorker? {
        val executor = scriptExecutorFactory.create(productId)
        return executor.initializeBot(botApi, scope).fold(
            onSuccess = { executor },
            onFailure = { error ->
                Timber.w(error, "No worker booted for product $productId")
                null
            },
        )
    }
}
