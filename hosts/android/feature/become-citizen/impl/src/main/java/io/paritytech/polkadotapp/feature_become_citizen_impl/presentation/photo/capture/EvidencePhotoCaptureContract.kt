package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture

import androidx.camera.core.SurfaceRequest
import androidx.lifecycle.LifecycleOwner
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.models.TattooOverlayUiState
import kotlinx.coroutines.flow.StateFlow

interface EvidencePhotoCaptureContract {
    val surfaceRequest: StateFlow<SurfaceRequest?>
    val tattooOverlayUiState: StateFlow<TattooOverlayUiState>

    suspend fun bindToCamera(lifecycleOwner: LifecycleOwner)

    fun back()
    fun takePhoto()

    fun toggleTattooOverlay()
}
