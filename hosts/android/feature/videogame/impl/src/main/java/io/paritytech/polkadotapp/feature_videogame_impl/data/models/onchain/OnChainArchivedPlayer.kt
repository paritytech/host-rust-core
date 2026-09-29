package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlinx.serialization.Serializable

@Serializable
sealed class OnChainArchivedPlayer {
    @Serializable
    class Kickable(val firstGame: GameIndex) : OnChainArchivedPlayer()

    @Serializable
    class Unkickable(val firstGame: GameIndex) : OnChainArchivedPlayer()
}

val OnChainArchivedPlayer.firstGame: GameIndex
    get() = when (this) {
        is OnChainArchivedPlayer.Kickable -> firstGame
        is OnChainArchivedPlayer.Unkickable -> firstGame
    }
