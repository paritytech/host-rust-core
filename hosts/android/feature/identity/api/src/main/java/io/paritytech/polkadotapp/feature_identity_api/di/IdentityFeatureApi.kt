package io.paritytech.polkadotapp.feature_identity_api.di

import io.paritytech.polkadotapp.feature_identity_api.data.repository.UserIdentityRepository
import io.paritytech.polkadotapp.feature_identity_api.data.storage.ClaimedUsernameStorage
import io.paritytech.polkadotapp.feature_identity_api.data.updaters.CredentialsUpdaters
import io.paritytech.polkadotapp.feature_identity_api.domain.CredentialPlatformsStateUseCase
import io.paritytech.polkadotapp.feature_identity_api.domain.TryRestoreUsernameUseCase

interface IdentityFeatureApi {
    val claimedUsernameStorage: ClaimedUsernameStorage
    val userIdentityRepository: UserIdentityRepository
    val credentialsUpdaters: CredentialsUpdaters
    val credentialPlatformsStateUseCase: CredentialPlatformsStateUseCase
    val tryRestoreUsernameUseCase: TryRestoreUsernameUseCase
}
