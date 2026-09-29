package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

data class VideoGameStages(
    val currentStage: Int,
    val stagesCount: Int
) {
    companion object {
        val Empty = VideoGameStages(0, 0)
    }
}
