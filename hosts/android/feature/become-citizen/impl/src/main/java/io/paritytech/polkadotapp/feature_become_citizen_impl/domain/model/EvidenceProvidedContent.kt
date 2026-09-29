package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.model

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.EvidenceType
import kotlinx.serialization.Serializable

@Serializable
data class EvidenceProvidedContent(val type: EvidenceType)
