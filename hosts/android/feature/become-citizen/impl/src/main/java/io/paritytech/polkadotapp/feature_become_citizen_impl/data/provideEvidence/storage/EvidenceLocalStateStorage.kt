package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.EvidenceLocalState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface EvidenceLocalStateStorage {
    fun subscribeState(type: EvidenceType): Flow<EvidenceLocalState>
    suspend fun setState(type: EvidenceType, state: EvidenceLocalState)
    suspend fun getState(type: EvidenceType): EvidenceLocalState
}

private const val PREFS_KEY_PREFIX = "evidence_state_"

class RealEvidenceLocalStateStorage @Inject constructor(
    private val preferences: Preferences
) : EvidenceLocalStateStorage {
    override fun subscribeState(type: EvidenceType): Flow<EvidenceLocalState> {
        return preferences.stringFlow(type.nameKey()).map { value ->
            val result = value?.let { enumValueOf(it) } ?: EvidenceLocalState.NOT_PRESENT
            return@map result
        }
    }

    override suspend fun setState(type: EvidenceType, state: EvidenceLocalState) {
        preferences.putString(type.nameKey(), state.name)
    }

    override suspend fun getState(type: EvidenceType): EvidenceLocalState {
        val savedState = preferences.getString(type.nameKey())?.let { enumValueOf<EvidenceLocalState>(it) }
        return savedState ?: EvidenceLocalState.NOT_PRESENT
    }

    private fun EvidenceType.nameKey(): String = PREFS_KEY_PREFIX + this.name
}
