package io.paritytech.polkadotapp.feature_coinage_api.domain.recycling

import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent

interface VoucherUsabilityContext {
    companion object;

    fun capacityFor(recyclerValue: ValueExponent): Int
}
