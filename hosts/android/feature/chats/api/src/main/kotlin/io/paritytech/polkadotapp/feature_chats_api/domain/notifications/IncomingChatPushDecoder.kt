package io.paritytech.polkadotapp.feature_chats_api.domain.notifications

import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessage
import io.paritytech.polkadotapp.feature_chats_api.domain.model.Contact

interface IncomingChatPushDecoder {
    suspend fun decode(data: Map<String, String>): Result<DecodedChatPush>

    companion object {
        const val PUSH_ID_KEY = "pushId"
        const val MESSAGE_KEY = "message"
    }
}

data class DecodedChatPush(
    val contact: Contact,
    val chatId: ChatId,
    val message: ChatMessage,
)
