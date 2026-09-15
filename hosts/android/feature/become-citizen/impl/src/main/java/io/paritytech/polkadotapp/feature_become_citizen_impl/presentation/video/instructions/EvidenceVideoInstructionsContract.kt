package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions

import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.video.instructions.models.PreconditionUiState
import kotlinx.coroutines.flow.StateFlow

interface EvidenceVideoInstructionsContract {
    val preconditionUiState: StateFlow<PreconditionUiState>

    fun back()
    fun openVideoRecorderIfPossible()

    fun dismissPrecondition()
    fun ignorePrecondition()
}
