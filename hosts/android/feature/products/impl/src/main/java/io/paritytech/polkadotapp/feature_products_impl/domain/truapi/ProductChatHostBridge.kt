package io.paritytech.polkadotapp.feature_products_impl.domain.truapi

import io.parity.truapi.ChatHostBridge
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.utils.childScope
import io.paritytech.polkadotapp.feature_chats_api.domain.extension.CreateRoomStatus
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductBotMessage
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.ProductChatMessaging
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.CreateProductRoomRequest
import io.paritytech.polkadotapp.feature_products_impl.domain.bot.model.ProductChatIdParameter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.plus
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import timber.log.Timber
import uniffi.truapi.ChatBotRegistrationStatus
import uniffi.truapi.ChatMessageContent
import uniffi.truapi.ChatRoom
import uniffi.truapi.ChatRoomRegistrationStatus
import uniffi.truapi_server.HostRejection
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

class ProductChatHostBridge(
    private val productId: ProductId,
    private val chatMessaging: ProductChatMessaging,
    workerScope: CoroutineScope,
    private val callTimeout: Duration = 2.seconds,
) : ChatHostBridge {

    private val detachedCalls = workerScope.childScope() + Dispatchers.Default

    override fun createRoom(roomId: String, name: String, icon: String): ChatRoomRegistrationStatus =
        awaitBlocking("createRoom") {
            chatMessaging.createRoom(CreateProductRoomRequest(ProductChatIdParameter(roomId), name, icon))
                .getOrThrow()
                .status
                .toCoreStatus()
        }

    override fun registerBot(botId: String, name: String, icon: String): ChatBotRegistrationStatus =
        throw HostRejection.Rejected("this host has no bot registry")

    override fun postMessage(roomId: String, content: ChatMessageContent): String {
        val message = content.toProductBotMessage()
            ?: throw HostRejection.Rejected(
                "this host cannot render a ${content.javaClass.simpleName} message",
            )
        return awaitBlocking("postMessage") {
            chatMessaging.sendMessage(ProductChatIdParameter(roomId), message).getOrThrow()
        }
    }

    override fun listRooms(): List<ChatRoom> = awaitBlocking("listRooms") {
        val rooms = chatMessaging.subscribeChatRooms().firstOrNull()
            ?: throw HostRejection.Rejected("no chat surface is bound; the host cannot list rooms")
        rooms.map { it.toCoreChatRoom() }
    }

    private fun <T> awaitBlocking(call: String, body: suspend () -> T): T = runBlocking {
        val work = detachedCalls.async { body() }
        val outcome = runCatching { withTimeoutOrNull(callTimeout) { work.await() } }
        val result = outcome.getOrElse { failure ->
            if (failure is HostRejection) throw failure
            Timber.w(failure, "truapi.chat.%s refused for %s", call, productId.value)
            throw HostRejection.Rejected("the host refused $call")
        }
        result ?: throw HostRejection.Rejected(
            "the host did not answer $call in time; the call may still have been applied",
        )
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

    private fun CreateRoomStatus.toCoreStatus(): ChatRoomRegistrationStatus = when (this) {
        CreateRoomStatus.New -> ChatRoomRegistrationStatus.NEW
        CreateRoomStatus.Exists -> ChatRoomRegistrationStatus.EXISTS
    }
}
