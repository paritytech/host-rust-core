package io.paritytech.polkadotapp.feature_become_citizen_api.domain.candidateState

interface CitizenshipApplyUseCase {
    suspend fun applyCitizenship(): Result<Unit>
}
