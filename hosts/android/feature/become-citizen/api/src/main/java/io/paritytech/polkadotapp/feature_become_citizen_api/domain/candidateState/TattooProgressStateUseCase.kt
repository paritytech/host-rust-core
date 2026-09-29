package io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.TattooProgressState
import kotlinx.coroutines.flow.Flow

interface TattooProgressStateUseCase {
    fun tattooProgressStateFlow(): Flow<Result<TattooProgressState>>

    suspend fun getTattooProgressState(): Result<TattooProgressState>
}
