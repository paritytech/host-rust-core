package io.paritytech.polkadotapp.feature_wallet_impl.domain.model

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress

enum class PocketRank {
    Basic, Member
}

fun VideoGamesProgress.toPocketRank(): PocketRank = when (this) {
    is VideoGamesProgress.FinalGameProcessing,
    is VideoGamesProgress.PlayingGames,
    is VideoGamesProgress.ReadyToReachPersonhood -> PocketRank.Basic

    is VideoGamesProgress.NotStarted -> if (isAlreadyPerson) PocketRank.Member else PocketRank.Basic

    VideoGamesProgress.ExternallyRecognized,
    is VideoGamesProgress.PersonhoodReached -> PocketRank.Member
}
