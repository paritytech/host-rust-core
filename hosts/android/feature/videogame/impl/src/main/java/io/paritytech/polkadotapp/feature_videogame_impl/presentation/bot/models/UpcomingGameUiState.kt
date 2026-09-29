package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models

import io.paritytech.polkadotapp.common.domain.model.Timestamp
import kotlin.time.Duration

sealed interface UpcomingGameUiState {
    val action: VideoGameActionNew?
    val isMember: Boolean

    data class Registration(
        val timeLeftUntilStart: Duration,
        val startsAt: Timestamp,
        override val action: VideoGameActionNew.Register,
        override val isMember: Boolean,
    ) : UpcomingGameUiState

    data class Registered(
        val timeLeftUntilStart: Duration,
        val startsAt: Timestamp,
        override val action: VideoGameActionNew.AddToCalendar,
        override val isMember: Boolean,
    ) : UpcomingGameUiState

    data class Starting(
        val timeLeftUntilStart: Duration,
        override val isMember: Boolean,
    ) : UpcomingGameUiState {
        override val action: VideoGameActionNew? = null
    }

    data object Ongoing : UpcomingGameUiState {
        override val action: VideoGameActionNew? = null
        override val isMember: Boolean = false
    }
}
