package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import kotlinx.serialization.Serializable

@Serializable
class OnChainVideoGamePhaseDurations(
    val registration: Long,
    val shuffle: Long,
    val postShuffleMargin: Long,
    val reporting: Long,
    val playerProcess: Long
)
