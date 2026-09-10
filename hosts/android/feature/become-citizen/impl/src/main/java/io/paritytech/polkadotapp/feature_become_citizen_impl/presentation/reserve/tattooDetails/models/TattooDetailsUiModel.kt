package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models.TattooSizeUiModel

@Immutable
data class TattooDetailsUiModel(
    val metadata: TattooMetadataUiModel,
    val size: TattooSizeUiModel,
    val evidenceReview: EvidenceReviewUiModel?
)
