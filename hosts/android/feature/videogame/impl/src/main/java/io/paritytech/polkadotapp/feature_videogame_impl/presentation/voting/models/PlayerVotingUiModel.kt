package io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.domain.model.AccountId

@Immutable
data class PlayerVotingUiModel(
    val accountId: AccountId,
    val picture: String,
    val isPerson: Boolean
)
