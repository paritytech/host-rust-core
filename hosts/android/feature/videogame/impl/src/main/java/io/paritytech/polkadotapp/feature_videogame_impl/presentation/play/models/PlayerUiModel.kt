package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.VideoTrack

@Immutable
data class PlayerUiModel(
    val accountId: AccountId,
    val videoTrack: VideoTrack?,
    val connection: PlayerConnectionState,
    val isHost: Boolean,
    val isCurrentPlayer: Boolean,
    val showGestureHintTooltip: Boolean,
    val isBanned: Boolean,
    val isSelectable: Boolean,
)

fun List<PlayerUiModel>.findHost() = find { it.isHost }
