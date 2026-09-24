package io.paritytech.polkadotapp.feature_products_impl.domain.bot.model

import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatExtensionId
import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatId

@JvmInline
value class ProductChatIdParameter(val value: String)

fun ProductChatIdParameter.toChatId(extensionId: ChatExtensionId): ChatId =
    if (value.isEmpty()) ChatId.forExtension(extensionId) else ChatId.forExtensionRoom(extensionId, value)
