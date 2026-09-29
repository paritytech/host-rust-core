package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel

val PlayerUiModel.sortResult: Int
    get() = when {
        isHost -> 0
        isCurrentPlayer -> 1
        else -> 2
    }

val PlayerUiModel.referenceId: String
    get() = accountId.layoutReferenceId

val AccountId.layoutReferenceId: String
    get() = value.contentHashCode().toString()

val PlayerUiModel.zIndex: Float
    get() = when {
        isHost -> 1f
        else -> 0f
    }

val PlayerUiModel.isConnected: Boolean
    get() = connection is PlayerConnectionState.Connected
