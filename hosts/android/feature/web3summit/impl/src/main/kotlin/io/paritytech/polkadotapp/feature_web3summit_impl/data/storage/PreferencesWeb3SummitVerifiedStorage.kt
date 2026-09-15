package io.paritytech.polkadotapp.feature_web3summit_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import javax.inject.Inject

class PreferencesWeb3SummitVerifiedStorage @Inject constructor(
    private val preferences: Preferences,
) {
    fun isVerified(): Boolean = preferences.getBoolean(KEY, false)

    fun setVerified(verified: Boolean) {
        preferences.putBoolean(KEY, verified)
    }

    companion object {
        private const val KEY = "web3_summit_verified"
    }
}
