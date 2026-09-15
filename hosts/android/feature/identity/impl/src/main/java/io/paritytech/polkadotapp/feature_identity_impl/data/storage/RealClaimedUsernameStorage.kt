package io.paritytech.polkadotapp.feature_identity_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_identity_api.data.storage.ClaimedUsernameStorage
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

private const val CLAIMED_USERNAME_KEY = "ClaimedUsername.Key"
private const val CLAIMED_USERNAME_DEFAULT = ""

class RealClaimedUsernameStorage @Inject constructor(
    private val preferences: Preferences
) : ClaimedUsernameStorage {
    override fun setClaimedUsername(username: String) {
        preferences.putString(CLAIMED_USERNAME_KEY, username)
    }

    override fun getClaimedUsername(): String = preferences.getString(
        CLAIMED_USERNAME_KEY,
        CLAIMED_USERNAME_DEFAULT
    )

    override fun getClaimedUsernameFlow(): Flow<String?> = preferences
        .stringFlow(
            field = CLAIMED_USERNAME_KEY,
            initialValueProducer = { CLAIMED_USERNAME_DEFAULT }
        )
}
