package io.paritytech.polkadotapp.feature_identity_api.domain

import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialConnection
import kotlinx.coroutines.flow.Flow

interface CredentialPlatformsStateUseCase {
    fun getIdentityCredentialStateFlow(): Flow<Result<List<IdentityCredentialConnection>>>
}
