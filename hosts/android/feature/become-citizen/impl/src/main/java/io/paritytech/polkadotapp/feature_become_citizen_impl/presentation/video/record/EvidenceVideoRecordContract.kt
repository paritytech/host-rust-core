package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record

import androidx.camera.core.SurfaceRequest
import androidx.lifecycle.LifecycleOwner
import kotlinx.coroutines.flow.StateFlow

interface EvidenceVideoRecordContract {
    val surfaceRequest: StateFlow<SurfaceRequest?>
    val state: StateFlow<VideoFileRecorder.State>

    suspend fun bindToCamera(lifecycleOwner: LifecycleOwner)

    fun back()
    fun toggleRecording()
}
