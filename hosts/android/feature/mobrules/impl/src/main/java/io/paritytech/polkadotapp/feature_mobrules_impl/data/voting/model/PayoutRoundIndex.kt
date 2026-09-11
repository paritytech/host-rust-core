package io.paritytech.polkadotapp.feature_mobrules_impl.data.voting.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import kotlinx.serialization.Serializable

@JvmInline
@Serializable
value class PayoutRoundIndex(val value: BigIntegerSerializable)
