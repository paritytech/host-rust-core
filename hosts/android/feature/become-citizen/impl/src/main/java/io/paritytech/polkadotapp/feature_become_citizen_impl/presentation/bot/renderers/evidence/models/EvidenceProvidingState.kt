package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.bot.renderers.evidence.models

import io.paritytech.polkadotapp.common.utils.Fraction

sealed interface EvidenceProvidingState {
    object Queued : EvidenceProvidingState
    data class Uploading(val progress: Fraction) : EvidenceProvidingState
    object InReview : EvidenceProvidingState
    object Approved : EvidenceProvidingState
    object Failed : EvidenceProvidingState
}
