package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.tattooDetails.models

import androidx.compose.runtime.Immutable
import kotlin.time.Duration

@Immutable
data class EvidenceReviewUiModel(
    val from: Duration,
    val to: Duration
)
