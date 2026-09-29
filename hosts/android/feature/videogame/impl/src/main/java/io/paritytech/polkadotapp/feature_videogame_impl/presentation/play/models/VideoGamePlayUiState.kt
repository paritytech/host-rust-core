package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models

import androidx.compose.runtime.Immutable
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.persistentListOf

@Immutable
data class VideoGamePlayUiState(
    val state: VideoGameUiState,
    val players: ImmutableList<PlayerUiModel>,
) {
    companion object {
        val Initial = VideoGamePlayUiState(
            state = VideoGameUiState.Initial,
            players = persistentListOf()
        )
    }
}
