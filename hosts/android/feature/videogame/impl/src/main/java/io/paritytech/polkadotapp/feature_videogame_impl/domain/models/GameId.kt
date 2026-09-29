package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.common.utils.toBigEndianByteArray
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex

@JvmInline
value class GameId private constructor(val value: ByteArray) {
    companion object {
        fun fromGameIndex(index: GameIndex): GameId {
            val gameBase = "pop:game:tpc                "
            val id = gameBase.toByteArray(Charsets.UTF_8) + index.value.toBigEndianByteArray()
            return GameId(id)
        }
    }
}
