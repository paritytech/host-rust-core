@file:OptIn(ExperimentalContracts::class)

package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.contract
import kotlin.time.Duration

internal fun isWaitingRoomJoinable(
    registrationStage: VideoGameRegistrationStage,
    processState: VideoGameProcessState?,
    gameTime: Duration?,
): Boolean {
    contract { returns(true) implies (gameTime != null) }
    return registrationStage is VideoGameRegistrationStage.Registered &&
        processState is VideoGameProcessState.WaitingRoom &&
        gameTime != null &&
        gameTime >= -VideoGameTimings.WAITING_ROOM_AVAILABLE_BEFORE
}
