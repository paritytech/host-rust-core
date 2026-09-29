package io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc

sealed interface PlayerConnectionState {
    data object Connecting : PlayerConnectionState
    data object Connected : PlayerConnectionState
    data object Disconnected : PlayerConnectionState
    data class Failed(val exception: Exception) : PlayerConnectionState
}
