package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.record

import android.Manifest
import androidx.camera.core.SurfaceRequest
import androidx.lifecycle.LifecycleOwner
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker
import io.paritytech.polkadotapp.common.utils.permissions.PermissionResult
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.EvidencesStorageConstants
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors.EvidenceVideoRecordInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.EvidenceVideoDurationConstants
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

@HiltViewModel
class EvidenceVideoRecordViewModel @Inject constructor(
    private val permissionAsker: PermissionAsker,
    private val recorder: VideoFileRecorder,
    private val interactor: EvidenceVideoRecordInteractor,
    private val router: BecomeCitizenRouter
) : BaseViewModel(), EvidenceVideoRecordContract {
    override val surfaceRequest = MutableStateFlow<SurfaceRequest?>(null)
    override val state = recorder.state

    override suspend fun bindToCamera(lifecycleOwner: LifecycleOwner) {
        val cameraPermission = permissionAsker.askPermission(Manifest.permission.CAMERA)

        if (cameraPermission == PermissionResult.GRANTED) {
            recorder.bind(lifecycleOwner) { surfaceRequest.value = it }
        } else {
            // TODO: Permission denied, handle accordingly (no mockups right now)
        }
    }

    override fun back() {
        val recordingState = state.value

        if (recordingState.isRecording) {
            launch {
                recorder.cancel()
                interactor.cleanUp()
                router.back()
            }
        } else {
            router.back()
        }
    }

    override fun toggleRecording() {
        if (state.value.isRecording) {
            recorder.stop()
        } else {
            prepareFileAndRecord()
        }
    }

    private fun prepareFileAndRecord() = launchUnit {
        val file = interactor.getDestinationFile()

        recorder.record(
            outputFile = file,
            maxDuration = EvidenceVideoDurationConstants.MAXIMUM,
            maxFileSize = EvidencesStorageConstants.VIDEO_SIZE_LIMIT
        ).onSuccess {
            val isCancelled = state.value.isCancelled

            if (isCancelled.not()) {
                val canProceed = interactor.finalizeRecording(state.value.duration)

                if (canProceed) {
                    router.openVideoPreview()
                } else {
                    recorder.reset()
                }
            }
        }.onFailure {
            Timber.e(it, "Error during recording")
        }
    }
}
