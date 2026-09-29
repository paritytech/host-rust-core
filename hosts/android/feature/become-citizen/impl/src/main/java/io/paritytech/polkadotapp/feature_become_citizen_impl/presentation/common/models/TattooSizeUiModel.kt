package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models

import androidx.compose.runtime.Immutable
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyMetadata
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooSize

@Immutable
sealed interface TattooSizeUiModel {
    companion object {
        fun fromMetadata(metadata: TattooFamilyMetadata) = when (val tattooSize = metadata.placement.size) {
            is TattooSize.Fixed -> Fixed(tattooSize.size.value)
            is TattooSize.Variable -> Variable(tattooSize.from.value, tattooSize.to.value)
        }
    }

    data class Fixed(val size: Int) : TattooSizeUiModel
    data class Variable(val from: Int, val to: Int) : TattooSizeUiModel
}
