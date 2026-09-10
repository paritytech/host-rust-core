package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.VideoTrack

data class VideoGamePlayer(
    val accountId: AccountId,
    val videoTrack: VideoTrack?,
    val connection: PlayerConnectionState,
    val isCurrentPlayer: Boolean,
    val isHost: Boolean
)

val VideoGamePlayer.isConnected: Boolean
    get() = connection is PlayerConnectionState.Connected
