package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models

import androidx.compose.runtime.Immutable
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

@Immutable
sealed interface VideoGameUiState {
    data object Initial : VideoGameUiState
    data class WaitingRoom(val timeLeft: Duration) : VideoGameUiState

    data class Connecting(val timeLeft: Duration) : VideoGameUiState {
        val camerasRevealed: Boolean get() = timeLeft < CAMERAS_REVEAL_THRESHOLD
    }

    data object HostIntroduction : VideoGameUiState
    data class Hosting(val duration: Duration, val timeLeft: Duration, val isEnding: Boolean) : VideoGameUiState
    data object HostReset : VideoGameUiState
    data object Finished : VideoGameUiState
    data object Error : VideoGameUiState
}

private val CAMERAS_REVEAL_THRESHOLD = 10.seconds
