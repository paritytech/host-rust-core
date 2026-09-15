package io.paritytech.polkadotapp.feature_videogame_impl.domain.chat

import io.paritytech.polkadotapp.feature_chats_api.domain.model.ChatOriginCustomConfiguration

class GameChatOriginConfiguration : ChatOriginCustomConfiguration {
    override fun paymentAvailable(): Boolean = false
}
