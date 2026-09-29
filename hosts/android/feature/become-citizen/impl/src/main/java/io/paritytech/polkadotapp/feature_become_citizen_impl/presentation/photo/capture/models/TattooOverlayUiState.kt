package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage

@Immutable
data class TattooOverlayUiState(
    val isVisible: Boolean = false,
    val tattooImage: TattooImage? = null
)
