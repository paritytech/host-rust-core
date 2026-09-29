package io.paritytech.polkadotapp.feature_videogame_impl.presentation.common.models

import io.paritytech.polkadotapp.common.domain.model.Timestamp
import kotlin.time.Duration

sealed interface UpcomingGameStartUiState {
    val timeLeftUntilStart: Duration
    val startsAt: Timestamp
    val action: VideoGameAction

    data class Current(
        override val timeLeftUntilStart: Duration,
        override val startsAt: Timestamp,
        override val action: VideoGameAction
    ) : UpcomingGameStartUiState

    data class Next(
        override val timeLeftUntilStart: Duration,
        override val startsAt: Timestamp,
        override val action: VideoGameAction
    ) : UpcomingGameStartUiState
}
