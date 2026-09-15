package io.paritytech.polkadotapp.feature_videogame_impl.data.repositories

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import kotlinx.coroutines.flow.Flow
import javax.inject.Inject

interface VideoGameKeepPlayingWarningRepository {
    fun userAcknowledgedWarningFlow(): Flow<Boolean>

    suspend fun resetWarningAcknowledgment()

    suspend fun warningAcknowledged()
}

internal class RealVideoGameKeepPlayingWarningRepository @Inject constructor(
    private val preferences: Preferences,
) : VideoGameKeepPlayingWarningRepository {
    companion object {
        private const val WARNING_PREF_KEY = "RealVideoGameKeepPlayingWarningRepository.KeepPlayingWarning"
    }

    override fun userAcknowledgedWarningFlow(): Flow<Boolean> {
        return preferences.booleanFlow(WARNING_PREF_KEY, defaultValue = false)
    }

    override suspend fun resetWarningAcknowledgment() {
        preferences.removeField(WARNING_PREF_KEY)
    }

    override suspend fun warningAcknowledged() {
        preferences.putBoolean(WARNING_PREF_KEY, true)
    }
}
