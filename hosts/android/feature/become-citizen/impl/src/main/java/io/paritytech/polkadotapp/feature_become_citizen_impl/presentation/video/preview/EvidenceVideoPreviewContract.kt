package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.preview

import android.net.Uri
import kotlinx.coroutines.flow.StateFlow

interface EvidenceVideoPreviewContract {
    val videoUri: StateFlow<Uri?>

    fun back()
    fun confirm()
}
