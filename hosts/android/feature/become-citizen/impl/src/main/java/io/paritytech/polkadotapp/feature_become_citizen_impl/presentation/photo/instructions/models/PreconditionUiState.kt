package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.instructions.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_become_citizen_impl.domain.evidences.models.ProvideEvidencePrecondition

@Immutable
data class PreconditionUiState(
    val isVisible: Boolean = false,
    val precondition: ProvideEvidencePrecondition? = null
)
