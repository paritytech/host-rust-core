@file:OptIn(ExperimentalContracts::class)

package io.paritytech.polkadotapp.feature_videogame_api.domain.state.model

import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract

sealed interface VideoGamesProgress {
    class NotStarted(val isAlreadyPerson: Boolean, val score: PersonhoodScore) : VideoGamesProgress

    object ExternallyRecognized : VideoGamesProgress

    sealed interface Started : VideoGamesProgress {
        /**
         * Index of the first game player has played. Null in case player has not played or registered to any game yet
         */
        val firstPlayedGame: GameIndex?
    }

    data class PlayingGames(
        override val firstPlayedGame: GameIndex?,
        /**
         * Confirmed score of the player, i.e. without considering potentially present currently active game
         */
        val score: PersonhoodScore,
        /**
         * Whether user has participated in the last game and this game its results are pending
         */
        val pendingGameResults: Boolean,
        val hasSuspendedPersonhood: Boolean,
    ) : Started

    data class FinalGameProcessing(
        override val firstPlayedGame: GameIndex?,
        val hasSuspendedPersonhood: Boolean
    ) : Started

    class ReadyToReachPersonhood(
        override val firstPlayedGame: GameIndex?,
    ) : Started

    class PersonhoodReached(
        override val firstPlayedGame: GameIndex?,
    ) : Started
}

fun VideoGamesProgress.participatesInDim2(): Boolean {
    contract {
        returns(true) implies (this@participatesInDim2 is VideoGamesProgress.Started)
        returns(false) implies (this@participatesInDim2 is VideoGamesProgress.NotStarted)
    }

    return this is VideoGamesProgress.Started
}

fun VideoGamesProgress.isExternallyRecognized(): Boolean {
    contract {
        returns(true) implies (this@isExternallyRecognized is VideoGamesProgress.ExternallyRecognized)
    }

    return this == VideoGamesProgress.ExternallyRecognized
}

fun VideoGamesProgress.isGamePlayerOnboardedViaAnotherDim(): Boolean {
    return this is VideoGamesProgress.ExternallyRecognized ||
        (this is VideoGamesProgress.NotStarted && isAlreadyPerson)
}

fun VideoGamesProgress.firstPlayedGame(): GameIndex? {
    return (this as? VideoGamesProgress.Started)?.firstPlayedGame
}
