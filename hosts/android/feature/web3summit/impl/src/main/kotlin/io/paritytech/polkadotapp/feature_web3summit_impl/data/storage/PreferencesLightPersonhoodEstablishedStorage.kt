package io.paritytech.polkadotapp.feature_web3summit_impl.data.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import javax.inject.Inject

class PreferencesLightPersonhoodEstablishedStorage @Inject constructor(
    private val preferences: Preferences,
) {
    fun isEstablished(): Boolean = preferences.getBoolean(KEY, false)

    fun setEstablished(established: Boolean) {
        preferences.putBoolean(KEY, established)
    }

    companion object {
        private const val KEY = "w3s_light_personhood_established"
    }
}
