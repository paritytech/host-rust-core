package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models

import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.HostingState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

fun VideoGameProcessState.toUi(gameTime: Duration): VideoGameUiState {
    return when (this) {
        is VideoGameProcessState.WaitingRoom -> {
            val timeLeft = (endsAt - gameTime).coerceAtLeast(Duration.ZERO)
            if (preConnection != null) {
                VideoGameUiState.Connecting(timeLeft)
            } else {
                VideoGameUiState.WaitingRoom(timeLeft)
            }
        }

        is VideoGameProcessState.Round -> {
            val timeLeft = (hostingState.endsAt - gameTime).coerceAtLeast(Duration.ZERO)

            when (hostingState) {
                is HostingState.Introduction -> VideoGameUiState.HostIntroduction
                is HostingState.Hosting -> VideoGameUiState.Hosting(hostingState.duration, timeLeft, false)
                is HostingState.Ending -> {
                    if (timeLeft <= 1.seconds) {
                        VideoGameUiState.HostReset
                    } else {
                        VideoGameUiState.Hosting(1.seconds, Duration.ZERO, true)
                    }
                }
            }
        }

        is VideoGameProcessState.Reporting,
        is VideoGameProcessState.Finished -> VideoGameUiState.Finished

        is VideoGameProcessState.Error -> VideoGameUiState.Error
    }
}
