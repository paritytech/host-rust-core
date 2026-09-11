package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.common.models

import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooFamilyIndex

sealed interface TattooFamilyUiIdentifier {
    data class Single(val index: TattooFamilyIndex) : TattooFamilyUiIdentifier
    data class Merged(val indexes: List<TattooFamilyIndex>) : TattooFamilyUiIdentifier
}
