package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.AsTuple
import kotlinx.serialization.Serializable

@Serializable
@AsTuple
data class OnChainVideoGamePlayerRoundKey(
    val roundIndex: Int,
    val playerIndex: Int
)
