package io.paritytech.polkadotapp.feature_become_citizen_impl.domain.model

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooIdCustomContent
import kotlinx.serialization.Serializable

@Serializable
data class SelectedTattooContent(
    val tattooId: TattooIdCustomContent,
    val tattooFamilyId: DataByteArray,
    val tattooFamilyName: String
)
