package io.paritytech.polkadotapp.feature_videogame_impl.data.models

import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.feature_videogame_api.domain.models.UpcomingGameStart
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings

fun UpcomingGameStart.isStartingSoon(currentTimestamp: Timestamp) = startsAt - currentTimestamp < VideoGameTimings.WAITING_ROOM_AVAILABLE_BEFORE.inWholeMilliseconds

val UpcomingGameStart.isWaitingRoomAvailable: Boolean
    get() = timeLeftUntilStart <= VideoGameTimings.WAITING_ROOM_AVAILABLE_BEFORE
