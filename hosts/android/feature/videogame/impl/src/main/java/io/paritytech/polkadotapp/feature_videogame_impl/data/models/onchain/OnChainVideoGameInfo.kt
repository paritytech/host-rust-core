package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlinx.serialization.Serializable

@Serializable
class OnChainVideoGameInfo(
    val index: GameIndex,
    val registrationEnds: Long,
    val gameDate: Long,
    val reportEnds: Long,
    val maxGroupSize: Int,
    val rounds: Int,
    val state: OnChainVideoGameState,
    val airdropsScheduled: Int
) {
    val airdropScheduled: Boolean
        get() = airdropsScheduled > 0
}

@Serializable
sealed class OnChainVideoGameState {
    @Serializable
    class Registration(val nextPlayerIndex: Int) : OnChainVideoGameState()

    @Serializable
    class Shuffle : OnChainVideoGameState()

    @Serializable
    class Reporting(val playerCount: Int) : OnChainVideoGameState()

    @Serializable
    object PlayerProcess : OnChainVideoGameState()

    @Serializable
    object Cancelling : OnChainVideoGameState()
}
