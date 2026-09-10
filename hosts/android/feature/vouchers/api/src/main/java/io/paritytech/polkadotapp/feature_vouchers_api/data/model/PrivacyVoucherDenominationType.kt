package io.paritytech.polkadotapp.feature_vouchers_api.data.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import kotlinx.serialization.Serializable

@Serializable
sealed class PrivacyVoucherDenominationType {
    @Serializable
    @TransientStruct
    class Fixed(val value: Balance) : PrivacyVoucherDenominationType()

    @Serializable
    @TransientStruct
    class Variable(val id: VariableVoucherId) : PrivacyVoucherDenominationType()
}

typealias VariableVoucherId = DataByteArray
