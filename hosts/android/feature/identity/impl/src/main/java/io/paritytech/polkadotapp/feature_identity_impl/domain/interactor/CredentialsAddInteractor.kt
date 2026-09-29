package io.paritytech.polkadotapp.feature_identity_impl.domain.interactor

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.feature_identity_api.data.repository.UserIdentityRepository
import io.paritytech.polkadotapp.feature_identity_api.data.storage.CredentialClaimedStorage
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform.Companion.platformName
import io.paritytech.polkadotapp.feature_transactions.api.data.requireOk
import javax.inject.Inject

interface CredentialsAddInteractor {
    suspend fun submitCredentials(platform: IdentityCredentialPlatform, credential: String): Result<Unit>
    suspend fun getClaimedUsername(): String
}

class RealCredentialsAddInteractor @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val userIdentityRepository: UserIdentityRepository,
    private val credentialClaimedStorage: CredentialClaimedStorage,
) : CredentialsAddInteractor {
    override suspend fun submitCredentials(platform: IdentityCredentialPlatform, credential: String): Result<Unit> {
        val chain = chainRegistry.peopleChain()

        return userIdentityRepository.submitCredentials(
            chain = chain,
            platform = platform,
            credential = credential
        ).onSuccess {
            val claimedCredential = IdentityCredentialPlatform.fromValue(
                platform.platformName(),
                credential
            ) ?: return@onSuccess
            credentialClaimedStorage.setCredentialClaimed(claimedCredential)
        }.mapCatching { it.requireOk() }
    }

    override suspend fun getClaimedUsername(): String {
        return userIdentityRepository.getClaimedUsername()
    }
}
