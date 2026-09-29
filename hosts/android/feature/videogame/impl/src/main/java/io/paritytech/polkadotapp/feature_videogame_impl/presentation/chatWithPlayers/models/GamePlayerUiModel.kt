package io.paritytech.polkadotapp.feature_videogame_impl.presentation.chatWithPlayers.models

import io.paritytech.polkadotapp.common.domain.model.AccountId

data class GamePlayerUiModel(
    val accountId: AccountId,
    val displayName: String,
    val avatarUri: String?,
    val contactStatus: ContactStatus
)

enum class ContactStatus {
    NOT_ADDED,
    ADDING,
    ADDED
}

enum class PlayerAction {
    ADD,
    MESSAGE
}
