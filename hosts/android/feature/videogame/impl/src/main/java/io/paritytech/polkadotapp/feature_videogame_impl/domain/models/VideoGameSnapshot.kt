package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex

data class VideoGameSnapshot(
    val gameIndex: GameIndex,
    val processState: VideoGameProcessState,
    val stages: VideoGameStages
)
