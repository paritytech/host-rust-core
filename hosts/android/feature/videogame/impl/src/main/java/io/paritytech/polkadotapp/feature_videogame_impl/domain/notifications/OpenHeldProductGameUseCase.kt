package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import kotlinx.coroutines.withContext
import javax.inject.Inject

class OpenHeldProductGameUseCase @Inject constructor(
    private val reminder: RealProductGameReminder,
    private val router: VideoGameRouter,
    private val coroutineDispatchers: CoroutineDispatchers,
) {
    suspend operator fun invoke(productId: ProductId) {
        withContext(coroutineDispatchers.main) { router.openGameProduct(productId) }
        reminder.currentSlot(productId)?.let { reminder.clear(it) }
    }
}
