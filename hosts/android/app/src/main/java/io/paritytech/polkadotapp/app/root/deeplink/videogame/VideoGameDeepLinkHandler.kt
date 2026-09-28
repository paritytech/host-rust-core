package io.paritytech.polkadotapp.app.root.deeplink.videogame

import android.net.Uri
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.deeplink.DeepLinkHandler
import io.paritytech.polkadotapp.common.presentation.deeplink.DeeplinkProcessingOutcome
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.isEnabled
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.awaitAccountsInitialized
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.deeplink.PRODUCT_GAME_PATH
import io.paritytech.polkadotapp.feature_videogame_impl.deeplink.WAITING_ROOM_PATH
import io.paritytech.polkadotapp.feature_videogame_impl.deeplink.WEEKLY_GAME_HOST
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.RealProductGameReminder
import io.paritytech.polkadotapp.feature_videogame_impl.utils.VideoGameLaunchCoordinator
import kotlinx.coroutines.withContext
import javax.inject.Inject

class VideoGameDeepLinkHandler @Inject constructor(
    private val coroutineDispatchers: CoroutineDispatchers,
    private val accountRepository: AccountRepository,
    private val videoGameRouter: VideoGameRouter,
    private val videoGameLaunchCoordinator: VideoGameLaunchCoordinator,
    private val productGameReminder: RealProductGameReminder,
) : DeepLinkHandler {
    override suspend fun canHandle(data: Uri): Boolean {
        if (data.scheme != DeepLinkHandler.APP_SCHEME || data.host != WEEKLY_GAME_HOST) return false

        // Safetynet builds switch PERSONHOOD off; the product game reminder still rings there.
        return FeatureOption.PERSONHOOD.isEnabled || data.pathSegments.firstOrNull() == PRODUCT_GAME_PATH
    }

    context(scope: ComputationalScope)
    override suspend fun handle(data: Uri): Result<DeeplinkProcessingOutcome> = withContext(coroutineDispatchers.io) {
        runCancellableCatching {
            accountRepository.awaitAccountsInitialized()

            val path = data.pathSegments.firstOrNull()

            when (path) {
                PRODUCT_GAME_PATH -> productGameReminder.currentSlot()?.let { slot ->
                    withContext(coroutineDispatchers.main) { videoGameRouter.openGameProduct(slot.productId) }
                    productGameReminder.clear(slot)
                }
                WAITING_ROOM_PATH -> withContext(coroutineDispatchers.main) {
                    videoGameRouter.openWeeklyGameBot()
                    videoGameLaunchCoordinator.launchGame()
                }
                else -> withContext(coroutineDispatchers.main) {
                    videoGameRouter.openWeeklyGameBot()
                }
            }

            DeeplinkProcessingOutcome.NoOp
        }
    }
}
