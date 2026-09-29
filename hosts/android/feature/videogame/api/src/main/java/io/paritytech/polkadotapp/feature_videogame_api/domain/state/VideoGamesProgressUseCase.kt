package io.paritytech.polkadotapp.feature_videogame_api.domain.state

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import kotlinx.coroutines.flow.Flow

interface VideoGamesProgressUseCase {
    context(scope: ComputationalScope)
    fun videoGamesProgressFlow(): Flow<VideoGamesProgress>

    context(scope: ComputationalScope)
    suspend fun videoGameProgress(): VideoGamesProgress
}
