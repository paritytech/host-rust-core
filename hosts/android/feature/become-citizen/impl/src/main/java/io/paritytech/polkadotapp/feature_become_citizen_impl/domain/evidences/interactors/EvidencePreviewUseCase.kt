package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors

import android.net.Uri
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.EvidenceLocalState
import kotlinx.coroutines.withContext
import javax.inject.Inject

class EvidencePreviewUseCase @Inject constructor(
    private val storage: EvidenceStorage,
    private val evidenceLocalStateStorage: EvidenceLocalStateStorage,
    private val coroutineDispatchers: CoroutineDispatchers
) {
    suspend fun getEvidenceUri(type: EvidenceType): Uri? = withContext(coroutineDispatchers.io) {
        val file = storage.getEvidenceFile(type)

        return@withContext if (file.exists() && file.canRead()) {
            Uri.fromFile(file)
        } else {
            null
        }
    }

    suspend fun confirm(type: EvidenceType) {
        evidenceLocalStateStorage.setState(type, EvidenceLocalState.CONFIRMED)
    }

    suspend fun cancel(type: EvidenceType) = withContext(coroutineDispatchers.io) {
        storage.getEvidenceFile(type).delete()
        evidenceLocalStateStorage.setState(type, EvidenceLocalState.NOT_PRESENT)
    }
}
