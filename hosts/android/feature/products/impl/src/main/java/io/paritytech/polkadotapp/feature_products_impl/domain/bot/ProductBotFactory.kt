package io.paritytech.polkadotapp.feature_products_impl.domain.bot

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_products_api.model.Product
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.e2e.E2EPendingChatMessages
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ProductWorkerRefCounter
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Factory for creating [ProductChatExtension] instances. The worker each extension drives is owned
 * by [ProductWorkerRefCounter], not built here.
 */
@Singleton
class ProductBotFactory @Inject constructor(
    @param:ApplicationContext private val appContext: Context,
    private val workerRefCounter: ProductWorkerRefCounter,
    private val pendingE2EMessages: E2EPendingChatMessages,
) {
    fun create(product: Product): ProductChatExtension {
        return ProductChatExtension(
            appContext = appContext,
            product = product,
            workerRefCounter = workerRefCounter,
            pendingE2EMessages = pendingE2EMessages,
        )
    }
}
