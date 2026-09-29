package io.paritytech.polkadotapp.feature_products_api.model

import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatMessageId

class JsUiEvent(
    val messageId: ChatMessageId,
    val chatId: ChatId,
    val actionId: String,
    val eventType: Type
) {
    sealed interface Type {
        object ButtonClick : Type

        class InputFieldValueChange(val newValue: String) : Type
    }
}
