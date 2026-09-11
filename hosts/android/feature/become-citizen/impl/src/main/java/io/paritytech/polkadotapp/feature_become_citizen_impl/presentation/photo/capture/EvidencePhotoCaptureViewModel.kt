package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture

import android.Manifest
import androidx.camera.core.SurfaceRequest
import androidx.lifecycle.LifecycleOwner
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker
import io.paritytech.polkadotapp.common.utils.permissions.PermissionResult
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.common.utils.toggle
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors.EvidencePhotoCaptureInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.models.TattooOverlayUiState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class EvidencePhotoCaptureViewModel @Inject constructor(
    private val permissionAsker: PermissionAsker,
    private val router: BecomeCitizenRouter,
    private val photoCapturer: PhotoFileCapturer,
    private val interactor: EvidencePhotoCaptureInteractor
) : BaseViewModel(), EvidencePhotoCaptureContract {
    override val surfaceRequest = MutableStateFlow<SurfaceRequest?>(null)

    private val tattooOverlayVisible = MutableStateFlow(true)
    private val tattooImageFlow = interactor.subscribeCommitedTattooImage().shareInBackground()

    override val tattooOverlayUiState = combine(
        tattooImageFlow,
        tattooOverlayVisible
    ) { tattooImage, isVisible ->
        TattooOverlayUiState(
            isVisible = isVisible,
            tattooImage = tattooImage
        )
    }.stateIn(this, SharingStarted.Eagerly, TattooOverlayUiState())

    override suspend fun bindToCamera(lifecycleOwner: LifecycleOwner) {
        val cameraPermission = permissionAsker.askPermission(Manifest.permission.CAMERA)

        if (cameraPermission == PermissionResult.GRANTED) {
            photoCapturer.bind(lifecycleOwner) { surfaceRequest.value = it }
        } else {
            // TODO: Permission denied, handle accordingly (no mockups right now)
        }
    }

    override fun back() {
        router.back()
    }

    override fun takePhoto() = launchUnit {
        val file = interactor.getDestinationFile()

        photoCapturer
            .takePicture(file)
            .onSuccess {
                interactor.finalizePhoto()
                router.openPhotoPreview()
            }
            .onFailure {
                interactor.cancelPhoto()
            }
    }

    override fun toggleTattooOverlay() {
        tattooOverlayVisible.toggle()
    }
}
