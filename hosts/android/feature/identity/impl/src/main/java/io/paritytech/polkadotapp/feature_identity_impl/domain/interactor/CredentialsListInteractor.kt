package io.paritytech.polkadotapp.feature_identity_impl.domain.interactor

import io.paritytech.polkadotapp.feature_identity_api.domain.CredentialPlatformsStateUseCase
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialConnection
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

interface CredentialsListInteractor {
    fun getIdentityCredentialConnectionsFlow(): Flow<Result<List<IdentityCredentialConnection>>>
}

class RealCredentialsListInteractor @Inject constructor(
    private val credentialPlatformsStateUseCase: CredentialPlatformsStateUseCase
) : CredentialsListInteractor {
    override fun getIdentityCredentialConnectionsFlow(): Flow<Result<List<IdentityCredentialConnection>>> {
        return credentialPlatformsStateUseCase.getIdentityCredentialStateFlow()
    }
}
