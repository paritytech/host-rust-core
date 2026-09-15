package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors

import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.FeatureFlags
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceLocalStateStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.EvidenceLocalState
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.EvidenceVideoDurationConstants
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import kotlin.time.Duration

class EvidenceVideoRecordInteractor @Inject constructor(
    private val storage: EvidenceStorage,
    private val evidenceLocalStateStorage: EvidenceLocalStateStorage,
    private val coroutineDispatchers: CoroutineDispatchers
) {
    suspend fun getDestinationFile(): File = withContext(coroutineDispatchers.io) {
        val file = storage.getEvidenceFile(EvidenceType.VIDEO)

        if (file.exists()) {
            file.delete()
        }

        return@withContext file
    }

    suspend fun finalizeRecording(currentDuration: Duration): Boolean = withContext(coroutineDispatchers.io) {
        val canProceed = if (FeatureFlags.isEnabled(FeatureOption.ALLOW_SHORT_EVIDENCE_VIDEO)) {
            true
        } else {
            currentDuration >= EvidenceVideoDurationConstants.MINIMUM
        }

        if (canProceed) {
            evidenceLocalStateStorage.setState(EvidenceType.VIDEO, EvidenceLocalState.PRESENT)
        } else {
            storage.getEvidenceFile(EvidenceType.VIDEO).delete()
            evidenceLocalStateStorage.setState(EvidenceType.VIDEO, EvidenceLocalState.NOT_PRESENT)
        }

        return@withContext canProceed
    }

    suspend fun cleanUp() = withContext(coroutineDispatchers.io) {
        storage.getEvidenceFile(EvidenceType.VIDEO).delete()
    }
}
