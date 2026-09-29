package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.reserve.list.models

import io.paritytech.polkadotapp.feature_tokens_api.presentation.model.TokenAmountModel

sealed interface TattooFamiliesVariant {
    data class Examples(val tokenAmount: TokenAmountModel) : TattooFamiliesVariant
    data object Selection : TattooFamiliesVariant
}
