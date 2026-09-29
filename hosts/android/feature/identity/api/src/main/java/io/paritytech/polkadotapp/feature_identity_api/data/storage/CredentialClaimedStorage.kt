package io.paritytech.polkadotapp.feature_identity_api.data.storage

import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialState

/**
 * We store [IdentityCredentialPlatform], that user claimed is his/hers. We need this only due to the
 * fact that we want to show [IdentityCredentialState.Rejected], which isn't get stored in the storage,
 * so the only way to know it was rejected - to check whether it was claimed or not. Hence, this storage.
 */
interface CredentialClaimedStorage {
    fun setCredentialClaimed(platform: IdentityCredentialPlatform)

    /**
     * @param platformName on of [IdentityCredentialPlatform.platformNames]
     */
    fun getClaimedCredentialForPlatform(platformName: String): IdentityCredentialPlatform?
}
