package io.paritytech.polkadotapp.feature_videogame_impl.presentation.common.models

import kotlin.time.Duration

sealed interface VideoGameAction {
    data class Register(val availability: Availability, val inProgress: Boolean) : VideoGameAction
    data class StartPlaying(val availability: Availability) : VideoGameAction
    data object Deposit : VideoGameAction

    sealed interface Availability {
        data object Available : Availability
        data class AvailableIn(val timeLeft: Duration) : Availability
    }
}
