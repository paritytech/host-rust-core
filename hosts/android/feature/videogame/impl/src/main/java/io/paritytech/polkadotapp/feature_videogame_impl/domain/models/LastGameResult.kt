package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex

sealed interface LastGameResult {
    data object Pending : LastGameResult

    data class Failed(val gameIndex: GameIndex) : LastGameResult
}
