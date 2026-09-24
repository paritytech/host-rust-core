package io.paritytech.polkadotapp.feature_products_impl.domain.worker

import dagger.Lazy
import io.paritytech.polkadotapp.feature_products_api.domain.runtime.ProductRuntimeSettings
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductsBotApi
import io.paritytech.polkadotapp.feature_products_impl.domain.scriptExecutor.HostApiProductsScriptExecutor
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.TrUAPIHostRuntimeProvider
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker.TrUAPIChatWorker
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.worker.TrUAPIWorkerSupervisor
import kotlinx.coroutines.CoroutineScope
import timber.log.Timber
import javax.inject.Inject

/**
 * Builds and starts a product's headless worker. Injected into [ProductWorkerRefCounter] once at
 * startup so the ref counter can be exercised without a real runtime, and so the product dependency
 * graph is assembled before any worker boots.
 */
interface WorkerBootFactory {
    suspend fun boot(
        productId: ProductId,
        botApi: ProductsBotApi,
        chatMessaging: ProductChatMessaging,
        scope: CoroutineScope,
    ): ProductWorker?
}

class RealWorkerBootFactory @Inject constructor(
    private val scriptExecutorFactory: HostApiProductsScriptExecutor.Factory,
    private val runtimeSettings: ProductRuntimeSettings,
    private val runtimeProvider: Lazy<TrUAPIHostRuntimeProvider>,
    private val workerSupervisor: Lazy<TrUAPIWorkerSupervisor>,
) : WorkerBootFactory {
    override suspend fun boot(
        productId: ProductId,
        botApi: ProductsBotApi,
        chatMessaging: ProductChatMessaging,
        scope: CoroutineScope,
    ): ProductWorker? {
        if (runtimeSettings.isTrUAPIRuntimeEnabled()) {
            bootCore(productId, chatMessaging, scope)?.let { return it }
        }
        return bootJs(productId, botApi, scope)
    }

    private suspend fun bootCore(
        productId: ProductId,
        chatMessaging: ProductChatMessaging,
        scope: CoroutineScope,
    ): ProductWorker? = runCatching {
        TrUAPIChatWorker(
            productId = productId,
            runtime = runtimeProvider.get().runtime().getOrThrow(),
            workers = workerSupervisor.get(),
            chatMessaging = chatMessaging,
            scope = scope,
        )
    }.getOrElse { error ->
        Timber.w(error, "TrUAPI worker unavailable for product $productId; falling back to the JS worker")
        null
    }

    private suspend fun bootJs(productId: ProductId, botApi: ProductsBotApi, scope: CoroutineScope): ProductWorker? {
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
