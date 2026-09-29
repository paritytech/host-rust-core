package io.paritytech.polkadotapp.feature_identity_impl

import io.paritytech.polkadotapp.common.presentation.navigation.ReturnableRouter
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform

interface IdentityRouter : ReturnableRouter {
    fun openAddCredentials(platform: IdentityCredentialPlatform)
    fun openCredentialsUnderReview()
    fun openCredentialsRejected(platform: IdentityCredentialPlatform)
    fun openMain()
}
