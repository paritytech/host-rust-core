package io.paritytech.polkadotapp.feature_products_impl.presentation.deeplink

import android.net.Uri
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler
import io.paritytech.polkadotapp.common.presentation.deeplink.DeeplinkProcessingOutcome
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.awaitAccountsInitialized
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderCenter
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderDeeplink
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.coroutines.withContext
import javax.inject.Inject

// Opening by product id skips the product deeplink gate, so only a product holding a reminder is opened: any app
// can send this link, but only a product the user has run can have scheduled one.
internal class GameReminderDeepLinkHandler @Inject constructor(
    private val dispatchers: CoroutineDispatchers,
    private val accountRepository: AccountRepository,
    private val center: GameReminderCenter,
    private val router: ProductsRouter,
) : DeepLinkHandler {
    override suspend fun canHandle(data: Uri): Boolean = GameReminderDeeplink.matches(data)

    context(scope: ComputationalScope)
    override suspend fun handle(data: Uri): Result<DeeplinkProcessingOutcome> = withContext(dispatchers.io) {
        runCancellableCatching {
            val productId = GameReminderDeeplink.productId(data)
                ?.takeIf { id -> center.reminders.value.any { it.productId == id } }
                ?: return@runCancellableCatching DeeplinkProcessingOutcome.NoOp

            accountRepository.awaitAccountsInitialized()

            DeeplinkProcessingOutcome.Navigate {
                router.openSpaBrowser(SpaBrowserPayload.ByProductId(productId))
            }
        }
    }
}
