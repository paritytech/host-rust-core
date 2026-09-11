package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors

import android.net.Uri
import androidx.media3.common.MediaItem
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.storage.EvidenceStorage
import kotlinx.coroutines.withContext
import javax.inject.Inject

class EvidenceVideoPreviewInteractor @Inject constructor(
    private val storage: EvidenceStorage,
    private val coroutineDispatchers: CoroutineDispatchers
) {
    suspend fun getMediaItem(): MediaItem? = withContext(coroutineDispatchers.io) {
        val file = storage.getEvidenceFile(EvidenceType.VIDEO)

        return@withContext if (file.exists() && file.canRead()) {
            MediaItem.fromUri(Uri.fromFile(file))
        } else {
            null
        }
    }

    suspend fun submitVideoEvidence() = withContext(coroutineDispatchers.io) {
        // TODO: implement worker to upload video evidence
    }
}
