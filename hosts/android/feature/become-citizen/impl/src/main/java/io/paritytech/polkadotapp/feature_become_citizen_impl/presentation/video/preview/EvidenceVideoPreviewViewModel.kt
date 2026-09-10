package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.preview

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.flowOf
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors.EvidencePreviewUseCase
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

@HiltViewModel
class EvidenceVideoPreviewViewModel @Inject constructor(
    private val router: BecomeCitizenRouter,
    private val evidencePreviewUseCase: EvidencePreviewUseCase
) : BaseViewModel(), EvidenceVideoPreviewContract {
    override val videoUri = flowOf {
        evidencePreviewUseCase.getEvidenceUri(EvidenceType.VIDEO)
    }.stateIn(this, SharingStarted.Eagerly, null)

    override fun back() = launchUnit {
        evidencePreviewUseCase.cancel(EvidenceType.VIDEO)
        router.back()
    }

    override fun confirm() = launchUnit {
        evidencePreviewUseCase.confirm(EvidenceType.VIDEO)
        router.popEvidenceVideo()
    }
}
