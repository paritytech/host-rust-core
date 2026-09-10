package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex

typealias GameAttendance = Set<GameIndex>

fun GameAttendance.earliestAttendedGame(): GameIndex? {
    return minOrNull()
}
