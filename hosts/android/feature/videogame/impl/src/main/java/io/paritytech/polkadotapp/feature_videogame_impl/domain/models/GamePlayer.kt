package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.common.domain.model.AccountId

data class GamePlayer(
    val accountId: AccountId,
    val displayName: String,
    val avatarUri: String?,
    val isAdded: Boolean
)
