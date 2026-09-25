package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.parity.truapi.ChatHostBridge
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_chats_api.domain.extension.CreateRoomStatus
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductBotMessage
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.CreateProductRoomRequest
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatIdParameter
import kotlinx.coroutines.flow.firstOrNull
import timber.log.Timber
import uniffi.truapi.ChatMessageContent
import uniffi.truapi.ChatRoom
import uniffi.truapi_server.HostRejection
import uniffi.truapi_server.NativeChatBotRegistrationStatus
import uniffi.truapi_server.NativeChatRoomRegistrationStatus

class ProductChatHostBridge(
    private val productId: ProductId,
    private val chatMessaging: ProductChatMessaging,
) : ChatHostBridge {

    override suspend fun createRoom(roomId: String, name: String, icon: String): NativeChatRoomRegistrationStatus {
        // An empty id names no room, and the chat identifier built from it would be malformed.
        if (roomId.isEmpty()) throw HostRejection.Rejected("a chat room needs an id")
        return chatMessaging.createRoom(CreateProductRoomRequest(ProductChatIdParameter(roomId), name, icon))
            .orReject()
            .status
            .toCoreStatus()
    }

    override suspend fun registerBot(botId: String, name: String, icon: String): NativeChatBotRegistrationStatus =
        throw HostRejection.Rejected("this host has no bot registry")

    override suspend fun postMessage(roomId: String, content: ChatMessageContent): String {
        if (roomId.isEmpty()) throw HostRejection.Rejected("a chat message needs a room")
        val message = content.toProductBotMessage()
            ?: throw HostRejection.Rejected(
                "this host cannot render a ${content.javaClass.simpleName} message",
            )
        return chatMessaging.sendMessage(ProductChatIdParameter(roomId), message).orReject()
    }

    override suspend fun listRooms(): List<ChatRoom> =
        chatMessaging.subscribeChatRooms().firstOrNull()?.map { it.toCoreChatRoom() } ?: emptyList()

    private fun <T> Result<T>.orReject(): T = getOrElse { failure ->
        if (failure is HostRejection) throw failure
        Timber.w(failure, "truapi.chat refused for %s", productId.value)
        throw HostRejection.Rejected(failure.message ?: failure.toString())
    }

    private fun ChatMessageContent.toProductBotMessage(): ProductBotMessage? = when (this) {
        is ChatMessageContent.Text -> ProductBotMessage.Text(text)
        is ChatMessageContent.Custom -> ProductBotMessage.Custom(v1.messageType, v1.payload.toDataByteArray())
        is ChatMessageContent.RichText,
        is ChatMessageContent.Actions,
        is ChatMessageContent.File,
        is ChatMessageContent.Reaction,
        is ChatMessageContent.ReactionRemoved,
        -> null
    }

    private fun CreateRoomStatus.toCoreStatus(): NativeChatRoomRegistrationStatus = when (this) {
        CreateRoomStatus.New -> NativeChatRoomRegistrationStatus.NEW
        CreateRoomStatus.Exists -> NativeChatRoomRegistrationStatus.EXISTS
    }
}
