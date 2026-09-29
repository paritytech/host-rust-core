package io.paritytech.polkadotapp.feature_videogame_impl.domain.mappers

import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePhaseDurations
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameSchedule
import kotlin.ranges.coerceAtLeast
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

fun OnChainVideoGameSchedule.timeLeftUntilStart(currentTime: Timestamp) =
    (getActualStartMillis() - currentTime).milliseconds.coerceAtLeast(Duration.ZERO)

fun OnChainVideoGameSchedule.timeLeftUntilRegistration(
    currentTime: Timestamp,
    phaseDurations: OnChainVideoGamePhaseDurations
): Duration {
    val registrationStartsAt = registrationStartsAtMillis(phaseDurations)
    return (registrationStartsAt - currentTime).milliseconds.coerceAtLeast(Duration.ZERO)
}

fun OnChainVideoGameSchedule.registrationStartsAtMillis(
    phaseDurations: OnChainVideoGamePhaseDurations
): Timestamp {
    val registrationOffsetSeconds = phaseDurations.registration +
        phaseDurations.shuffle +
        phaseDurations.postShuffleMargin

    return (gameStartSeconds - registrationOffsetSeconds) * 1000
}

fun OnChainVideoGameSchedule.getActualStartMillis() = gameStartSeconds.seconds.inWholeMilliseconds
