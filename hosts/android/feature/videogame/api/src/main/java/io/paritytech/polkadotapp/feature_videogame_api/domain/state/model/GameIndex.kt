package io.paritytech.polkadotapp.feature_videogame_api.domain.state.model

import kotlinx.serialization.Serializable

@JvmInline
@Serializable
value class GameIndex(val value: Int) : Comparable<GameIndex> {
    companion object {
        fun zero(): GameIndex {
            return GameIndex(0)
        }
    }

    override fun compareTo(other: GameIndex): Int {
        return value.compareTo(other.value)
    }

    operator fun plus(other: Int): GameIndex {
        return GameIndex(value + other)
    }
}
