package io.paritytech.polkadotapp.feature_products_impl.domain.bot

import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.CreateProductRoomRequest
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.CreateProductRoomResult
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatIdParameter
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatRoom
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.CallingProductIdProvider
import io.paritytech.polkadotapp.feature_products_impl.domain.hostApi.HostApiInteractor
import io.paritytech.polkadotapp.feature_products_impl.domain.jsEngine.HostCallException
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.ModalityApiSlot
import io.paritytech.polkadotapp.feature_products_impl.domain.worker.WeakModalityApiSlot
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emptyFlow

private const val MESSAGING_NOT_SUPPORTED_CODE = "messaging_not_supported"

// The ProductsBotApi a shared worker boots with. General host calls always work through
// BaseProductsBotApi; the chat-messaging calls route to whatever ProductChatMessaging is bound in
// chatSlot, and fail cleanly when nothing is bound.
class BindableProductsBotApi(
    hostApiInteractor: HostApiInteractor,
    callingProductIdProvider: CallingProductIdProvider,
) : BaseProductsBotApi(hostApiInteractor, callingProductIdProvider) {
    val chatSlot: ModalityApiSlot<ProductChatMessaging> = WeakModalityApiSlot()

    override suspend fun createRoom(request: CreateProductRoomRequest): Result<CreateProductRoomResult> {
        return chatSlot.tryUse().fold(
            onSuccess = { it.createRoom(request) },
            onFailure = { messagingNotSupported() },
        )
    }

    override suspend fun sendMessage(
        chatIdParameter: ProductChatIdParameter,
        message: ProductBotMessage,
    ): Result<ChatMessageId> {
        return chatSlot.tryUse().fold(
            onSuccess = { it.sendMessage(chatIdParameter, message) },
            onFailure = { messagingNotSupported() },
        )
    }

    override fun subscribeChatRooms(): Flow<List<ProductChatRoom>> {
        return chatSlot.tryUse().getOrNull()?.subscribeChatRooms() ?: emptyFlow()
    }

    private fun <T> messagingNotSupported(): Result<T> = Result.failure(
        HostCallException(MESSAGING_NOT_SUPPORTED_CODE, "Product messaging is not supported in this context")
    )
}
