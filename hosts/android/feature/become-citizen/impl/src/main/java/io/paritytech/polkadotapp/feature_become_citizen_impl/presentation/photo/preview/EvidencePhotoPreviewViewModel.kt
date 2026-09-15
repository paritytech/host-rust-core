package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.preview

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.feature_become_citizen_api.data.upload.EvidenceUploadStarter
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors.EvidencePreviewUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class EvidencePhotoPreviewViewModel @Inject constructor(
    private val router: BecomeCitizenRouter,
    private val evidencePreviewUseCase: EvidencePreviewUseCase,
    private val evidenceUploadStarter: EvidenceUploadStarter
) : BaseViewModel(), EvidencePhotoPreviewContract {
    override val photoUri = flowOf {
        evidencePreviewUseCase.getEvidenceUri(EvidenceType.PHOTO)
    }.stateIn(this, SharingStarted.Eagerly, null)

    override fun back() = launchUnit {
        evidencePreviewUseCase.cancel(EvidenceType.PHOTO)
        router.back()
    }

    override fun confirm() = launchUnit {
        evidencePreviewUseCase.confirm(EvidenceType.PHOTO)
        evidenceUploadStarter.startUpload()
        router.popEvidencePhoto()
    }
}
