package io.paritytech.polkadotapp.feature_identity_api.data.storage

import kotlinx.coroutines.flow.Flow

interface ClaimedUsernameStorage {
    fun setClaimedUsername(username: String)
    fun getClaimedUsername(): String
    fun getClaimedUsernameFlow(): Flow<String?>
}
