package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import javax.inject.Inject

interface DepositTrackingRepository {
    suspend fun setUserPutDeposit(userPutDeposit: Boolean)

    suspend fun didUserPutDeposit(): Boolean
}

class RealDepositTrackingRepository @Inject constructor(
    private val preferences: Preferences
) : DepositTrackingRepository {
    companion object {
        private const val PREFS_KEY = "RealDepositTrackingRepository.UserPutDeposit"
        private const val DEFAULT_VALUE = false
    }

    override suspend fun setUserPutDeposit(userPutDeposit: Boolean) {
        preferences.putBoolean(PREFS_KEY, userPutDeposit)
    }

    override suspend fun didUserPutDeposit(): Boolean {
        return preferences.getBoolean(PREFS_KEY, DEFAULT_VALUE)
    }
}
