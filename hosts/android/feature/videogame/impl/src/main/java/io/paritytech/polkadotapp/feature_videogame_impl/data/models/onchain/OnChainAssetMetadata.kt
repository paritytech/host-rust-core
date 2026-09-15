package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.serializers.BigIntegerSerializable
import kotlinx.serialization.Serializable

@Serializable
class OnChainAssetMetadata(
    val deposit: BigIntegerSerializable,
    val name: String,
    val symbol: String,
    val decimals: Byte,
    val isFrozen: Boolean,
)
