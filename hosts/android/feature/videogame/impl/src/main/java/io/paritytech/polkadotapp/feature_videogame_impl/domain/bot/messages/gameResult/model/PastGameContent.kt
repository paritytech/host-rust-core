package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot.messages.gameResult.model

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.annotations.EnumIndex
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import kotlinx.serialization.Serializable

@Serializable
data class PastGameContent(
    val outcome: PastGameOutcome,
    val gameIndex: GameIndex,
    val timestamp: Timestamp,
    val playerAvatarPaths: List<String>
)

@Serializable
sealed interface PastGameOutcome {
    @Serializable
    @EnumIndex(0)
    data object Pending : PastGameOutcome

    @Serializable
    @EnumIndex(1)
    data class Success(val scoring: SuccessPastGameScoring) : PastGameOutcome

    @Serializable
    @EnumIndex(2)
    data class Failed(val scoring: FailedPastGameScoring) : PastGameOutcome
}

@Serializable
sealed interface SuccessPastGameScoring {
    @Serializable
    @EnumIndex(0)
    data object ReachedPersonhood : SuccessPastGameScoring

    /**
     * We use [Playing] when we are emitting results of the current last game
     */
    @Serializable
    @EnumIndex(1)
    data class Playing(val gamesLeft: Int, val hasSuspendedPersonhood: Boolean) : SuccessPastGameScoring

    /**
     * We use [PersonhoodStateUnknown] instead of [Playing] or [ReachedPersonhood] when we are emitting the game results that is not the last
     * Constructing [Playing.gamesLeft] for such games is not trivial and thus we avoid doing so (yet)
     */
    @Serializable
    @EnumIndex(2)
    data object PersonhoodStateUnknown : SuccessPastGameScoring

    @Serializable
    @EnumIndex(3)
    data object ExternallyRecognized : SuccessPastGameScoring

    @Serializable
    @EnumIndex(4)
    data object AlreadyReachedPersonhood : SuccessPastGameScoring
}

@Serializable
sealed interface FailedPastGameScoring {
    /**
     * @see SuccessPastGameScoring.Playing
     */
    @Serializable
    @EnumIndex(0)
    data class Playing(val gamesLeft: Int, val hasSuspendedPersonhood: Boolean) : FailedPastGameScoring

    /**
     * @see SuccessPastGameScoring.PersonhoodStateUnknown
     */
    @Serializable
    @EnumIndex(1)
    data object PersonhoodStateUnknown : FailedPastGameScoring

    @Serializable
    @EnumIndex(2)
    data object ExternallyRecognized : FailedPastGameScoring
}
