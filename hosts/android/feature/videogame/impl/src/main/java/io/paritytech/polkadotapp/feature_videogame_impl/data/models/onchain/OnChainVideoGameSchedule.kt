package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
class OnChainVideoGameSchedule(
    @SerialName("gamePlayTime") val gameStartSeconds: Long,
    val rounds: Int,
    val maxGroupSize: Int
)
