package io.paritytech.polkadotapp.app.root.navigation.products

import io.paritytech.polkadotapp.app.R
import io.paritytech.polkadotapp.app.root.navigation.BaseNavigator
import io.paritytech.polkadotapp.app.root.navigation.NavigationHolder
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.toPayloadBundle
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_api.presentation.model.ChatFeedPayload
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_api.model.toChatExtensionId
import io.paritytech.polkadotapp.feature_products_api.presentation.ProductSettingsPayload
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.coroutines.withContext
import javax.inject.Inject

class ProductsNavigator @Inject constructor(
    navigationHolder: NavigationHolder,
    private val dispatchers: CoroutineDispatchers,
) : BaseNavigator(navigationHolder), ProductsRouter {
    override suspend fun openSignTransaction() = withContext(dispatchers.main) {
        performNavigation(R.id.action_global_to_transactionSignBottomSheet)
    }

    override fun openSpaBrowser(payload: SpaBrowserPayload) = performNavigation(
        actionId = R.id.action_global_to_spaBrowserFragment,
        args = payload.toPayloadBundle(SpaBrowserPayload::class.java.name),
    )

    override fun leaveBrowser() {
        back()
    }

    override fun openProductChat(productId: ProductId) {
        performNavigation(
            actionId = R.id.action_global_to_chatFeedFragment,
            args = ChatFeedPayload.botChat(productId.toChatExtensionId()).toPayloadBundle(),
        )
    }

    override fun openChat(chatId: ChatId) {
        performNavigation(
            actionId = R.id.action_global_to_chatFeedFragment,
            args = ChatFeedPayload.existingChat(chatId).toPayloadBundle(),
        )
    }

    override fun openProductSettings(productId: ProductId) {
        performNavigation(
            actionId = R.id.action_productList_to_productSettings,
            args = ProductSettingsPayload(productId = productId.value).toPayloadBundle()
        )
    }

    override fun openProductPermissions(productId: ProductId) {
        performNavigation(
            actionId = R.id.action_productSettings_to_permissionSettings,
            args = ProductSettingsPayload(productId = productId.value).toPayloadBundle()
        )
    }

    override suspend fun openPermissionPrompt() = withContext(dispatchers.main) {
        performNavigation(R.id.action_global_to_permissionPromptBottomSheet)
    }

    override suspend fun openPaymentRequestPrompt() = withContext(dispatchers.main) {
        performNavigation(R.id.action_global_to_paymentRequestBottomSheet)
    }

    override suspend fun openTopUpRequestPrompt() = withContext(dispatchers.main) {
        performNavigation(R.id.action_global_to_topUpRequestBottomSheet)
    }

    override suspend fun openResourceAllocationRequestPrompt() = withContext(dispatchers.main) {
        performNavigation(R.id.action_global_to_resourceAllocationRequestBottomSheet)
    }

    override suspend fun openCrossProductProofPrompt() = withContext(dispatchers.main) {
        performNavigation(R.id.action_global_to_crossProductProofBottomSheet)
    }
}
