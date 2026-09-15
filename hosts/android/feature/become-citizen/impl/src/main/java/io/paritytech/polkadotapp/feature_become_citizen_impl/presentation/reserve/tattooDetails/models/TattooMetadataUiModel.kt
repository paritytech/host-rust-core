package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImage

@Immutable
data class TattooMetadataUiModel(
    val title: String,
    val description: String,
    val image: TattooImage
)
