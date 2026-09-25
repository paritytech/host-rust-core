package io.paritytech.polkadotapp.feature_products_impl.domain.product

import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.data.repository.ProductRepository
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderCenter
import io.paritytech.polkadotapp.feature_products_impl.domain.notifications.ProductNotificationScheduler
import javax.inject.Inject

class UninstallProductUseCase @Inject constructor(
    private val productRepository: ProductRepository,
    private val notificationScheduler: ProductNotificationScheduler,
    private val gameReminderCenter: GameReminderCenter,
) {
    suspend operator fun invoke(productId: ProductId): Result<Unit> {
        return notificationScheduler.cancelAllForProduct(productId)
            .map {
                gameReminderCenter.cancel(productId.value)
                productRepository.deleteProduct(productId)
            }
    }
}
