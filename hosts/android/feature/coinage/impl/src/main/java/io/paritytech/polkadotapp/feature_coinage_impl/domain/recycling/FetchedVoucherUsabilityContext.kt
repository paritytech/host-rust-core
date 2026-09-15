package io.paritytech.polkadotapp.feature_coinage_impl.domain.recycling

import io.paritytech.polkadotapp.feature_coinage_api.domain.model.ValueExponent
import io.paritytech.polkadotapp.feature_coinage_api.domain.recycling.VoucherUsabilityContext

data class FetchedVoucherUsabilityContext(
    val ringCapacities: Map<ValueExponent, Int>,
) : VoucherUsabilityContext {
    override fun capacityFor(recyclerValue: ValueExponent): Int = ringCapacities[recyclerValue] ?: Int.MAX_VALUE
}

class ImmediateVoucherUsabilityContext : VoucherUsabilityContext {
    companion object {
        private const val COINAGE_DEFAULT_CAPACITY = 767
    }

    override fun capacityFor(recyclerValue: ValueExponent): Int {
        return COINAGE_DEFAULT_CAPACITY
    }
}
