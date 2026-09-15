package io.paritytech.polkadotapp.feature_identity_api.domain.models

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class IdentityOf(
    val info: IdentityOfInfo
)

@Serializable
data class IdentityOfInfo(
    val twitter: OnChainIdentityField,
    val github: OnChainIdentityField,
    val discord: OnChainIdentityField,
)

@Serializable
sealed interface OnChainIdentityField {
    @Serializable
    @TransientStruct
    @SerialName("Raw")
    data class Raw(val value: String) : OnChainIdentityField

    @Serializable
    @SerialName("None")
    data object None : OnChainIdentityField
}

fun OnChainIdentityField.value(): String? {
    return when (this) {
        is OnChainIdentityField.Raw -> value
        OnChainIdentityField.None -> null
    }
}
