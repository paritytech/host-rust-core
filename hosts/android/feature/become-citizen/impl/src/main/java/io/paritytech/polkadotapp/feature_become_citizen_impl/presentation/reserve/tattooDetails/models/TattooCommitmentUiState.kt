package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models

import androidx.compose.runtime.Immutable

@Immutable
data class TattooCommitmentUiState(
    val isVisible: Boolean = false,
    val inProgress: Boolean = false
)
