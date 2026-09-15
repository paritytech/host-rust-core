package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.upload

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.feature_become_citizen_api.data.upload.EvidenceUploadStarter
import javax.inject.Inject

class RealEvidenceUploadStarter @Inject constructor(
    @param:ApplicationContext private val appContext: Context
) : EvidenceUploadStarter {
    override fun startUpload() {
        EvidenceUploadWorker.startEvidenceUpload(appContext)
    }
}
