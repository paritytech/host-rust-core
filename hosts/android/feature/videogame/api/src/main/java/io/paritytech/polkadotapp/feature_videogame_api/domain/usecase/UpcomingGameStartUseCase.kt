package io.paritytech.polkadotapp.feature_videogame_api.domain.usecase

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_videogame_api.domain.models.UpcomingGameStart
import kotlinx.coroutines.flow.Flow

interface UpcomingGameStartUseCase {
    context(scope: ComputationalScope)
    fun subscribe(): Flow<UpcomingGameStart?>
}
