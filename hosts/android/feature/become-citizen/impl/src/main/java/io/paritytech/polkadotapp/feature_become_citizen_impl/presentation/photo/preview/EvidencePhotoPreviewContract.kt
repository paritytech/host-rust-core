package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.preview

import android.net.Uri
import kotlinx.coroutines.flow.StateFlow

interface EvidencePhotoPreviewContract {
    val photoUri: StateFlow<Uri?>

    fun back()
    fun confirm()
}
