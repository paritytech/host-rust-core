package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.annotations.TransientStruct
import io.paritytech.polkadotapp.chains.network.binding.Balance
import io.paritytech.polkadotapp.feature_people_api.domain.models.PersonId
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.PersonhoodScore
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
class OnChainParticipant(
    val score: Int,
    val streak: OnChainVideoGameStreak,
    val credit: Balance,
    val cashedOut: Boolean,
    @SerialName("reachedPersonhood")
    val reachedPersonhoodLastAttendance: Boolean,
    val hasEverReachedPersonhood: Boolean,
    val recognition: OnChainVideoGameRecognition
)

@Serializable
sealed interface OnChainVideoGameStreak {
    val count: Int

    @JvmInline
    @Serializable
    value class Attended(override val count: Int) : OnChainVideoGameStreak

    @JvmInline
    @Serializable
    value class Absent(override val count: Int) : OnChainVideoGameStreak
}

@Serializable
sealed interface OnChainVideoGameRecognition {
    @Serializable
    data object NotRecognized : OnChainVideoGameRecognition

    @Serializable
    data object ExternallyRecognized : OnChainVideoGameRecognition

    @Serializable
    @TransientStruct
    data class Recognized(val personalId: PersonId) : OnChainVideoGameRecognition

    @Serializable
    @TransientStruct
    data class Suspended(val personalId: PersonId) : OnChainVideoGameRecognition
}

@JvmName("calculatePersonhoodScoreOrDefault")
fun OnChainParticipant?.calculatePersonhoodScore(personhoodThreshold: Int): PersonhoodScore {
    return this?.calculatePersonhoodScore(personhoodThreshold)
        ?: calculatePendingPersonhoodScore(currentScore = 0, attendedStreak = 0, personhoodThreshold)
}

fun OnChainParticipant.calculatePersonhoodScore(personhoodThreshold: Int): PersonhoodScore {
    if (reachedPersonhoodLastAttendance) return PersonhoodScore(current = score, target = score, gamesLeft = 0)

    return calculatePendingPersonhoodScore(
        currentScore = score,
        attendedStreak = streak.getAttendedStreakSize(),
        personhoodThreshold = personhoodThreshold
    )
}

/**
 * Mirrors the runtime's `Recognition::is_recognized()` — the check `register_for_airdrop` uses to
 * decide which airdrop proof variant a sign-up must carry (recognized -> Alias, else Account).
 */
fun OnChainVideoGameRecognition.isRecognized(): Boolean {
    return when (this) {
        OnChainVideoGameRecognition.ExternallyRecognized,
        is OnChainVideoGameRecognition.Recognized -> true

        OnChainVideoGameRecognition.NotRecognized,
        is OnChainVideoGameRecognition.Suspended -> false
    }
}

fun OnChainVideoGameRecognition.isRecognizedViaGames(): Boolean {
    return when (this) {
        OnChainVideoGameRecognition.NotRecognized,
        OnChainVideoGameRecognition.ExternallyRecognized,
        is OnChainVideoGameRecognition.Suspended -> false

        is OnChainVideoGameRecognition.Recognized -> true
    }
}

/**
 * Returns the number of remaining games under assumption that user has not yet reached personhood
 * so the return value is strictly positive and cannot be zero
 */
fun calculatePendingPersonhoodScore(
    currentScore: Int,
    attendedStreak: Int,
    personhoodThreshold: Int
): PersonhoodScore {
    var gamesNeeded = 0
    var gameIndex = -1
    var simulatedScore = currentScore
    var simulatedStreak = attendedStreak

    do {
        gamesNeeded++
        gameIndex++
        simulatedStreak++
        simulatedScore += simulatedStreak
    } while (simulatedScore < personhoodThreshold)

    return PersonhoodScore(
        current = currentScore,
        target = personhoodThreshold,
        gamesLeft = gamesNeeded
    )
}

private fun OnChainVideoGameStreak.getAttendedStreakSize() = when (this) {
    is OnChainVideoGameStreak.Attended -> count
    is OnChainVideoGameStreak.Absent -> 0
}
