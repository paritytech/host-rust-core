package io.paritytech.polkadotapp.feature_videogame_api.domain.models

import io.paritytech.polkadotapp.common.domain.model.Timestamp
import kotlin.time.Duration

sealed interface UpcomingGameStart {
    val timeLeftUntilStart: Duration
    val startsAt: Timestamp

    data class Current(
        override val startsAt: Timestamp,
        override val timeLeftUntilStart: Duration
    ) : UpcomingGameStart

    data class Next(
        override val startsAt: Timestamp,
        override val timeLeftUntilStart: Duration,
        val timeLeftUntilRegistrationOpens: Duration
    ) : UpcomingGameStart
}
