package io.paritytech.polkadotapp.feature_videogame_impl.data.models

import kotlinx.serialization.Serializable

typealias FullVideoGameReport = List<List<VideoGameReport>>

@Serializable
sealed class VideoGameReport {
    @Serializable
    data object Person : VideoGameReport()

    @Serializable
    data object NotPerson : VideoGameReport()
}
