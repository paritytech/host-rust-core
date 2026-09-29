package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.interactors.EvidenceVideoInstructionsInteractor
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.BecomeCitizenRouter
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions.models.PreconditionUiState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import javax.inject.Inject

@HiltViewModel
class EvidenceVideoInstructionsViewModel @Inject constructor(
    private val router: BecomeCitizenRouter,
    private val interactor: EvidenceVideoInstructionsInteractor
) : BaseViewModel(), EvidenceVideoInstructionsContract {
    override val preconditionUiState = MutableStateFlow(PreconditionUiState())

    override fun back() {
        router.back()
    }

    override fun openVideoRecorderIfPossible() {
        val precondition = interactor.checkPreconditions()
        if (precondition != null) {
            preconditionUiState.value = PreconditionUiState(
                isVisible = true,
                precondition = precondition
            )
        } else {
            router.openVideoRecorder()
        }
    }

    override fun dismissPrecondition() {
        preconditionUiState.update { it.copy(isVisible = false) }
    }

    override fun ignorePrecondition() {
        dismissPrecondition()
        router.openVideoRecorder()
    }
}
