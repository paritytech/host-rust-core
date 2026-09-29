package io.paritytech.polkadotapp.feature_identity_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_identity_api.data.storage.CredentialClaimedStorage
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform
import io.paritytech.polkadotapp.feature_identity_api.domain.models.IdentityCredentialPlatform.Companion.platformName
import javax.inject.Inject

private const val CREDENTIAL_CLAIMED_PREFIX = "CredentialClaimed."

class RealCredentialClaimedStorage @Inject constructor(
    private val preferences: Preferences
) : CredentialClaimedStorage {
    override fun setCredentialClaimed(platform: IdentityCredentialPlatform) {
        val key = CREDENTIAL_CLAIMED_PREFIX + platform.platformName()
        preferences.putString(key, platform.username)
    }

    override fun getClaimedCredentialForPlatform(
        platformName: String
    ): IdentityCredentialPlatform? {
        val key = CREDENTIAL_CLAIMED_PREFIX + platformName
        val username = preferences.getString(key)
        return if (username.isNullOrBlank()) null else IdentityCredentialPlatform.fromValue(platformName, username)
    }
}
