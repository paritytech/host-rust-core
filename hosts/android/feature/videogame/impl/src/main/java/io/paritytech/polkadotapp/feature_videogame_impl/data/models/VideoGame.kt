package io.paritytech.polkadotapp.feature_videogame_impl.data.models

import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainAssetWithAmount
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.feature_people_api.domain.invitation.IssuedInvitation
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.GameId
import kotlin.time.Duration.Companion.milliseconds

// TODO this should be in domain layer
class VideoGameInfo(
    val index: GameIndex,
    val registrationEnd: Timestamp,
    val gameStartMillis: Timestamp,
    val reportEnd: Timestamp,
    val rounds: Int,
    val preferredMaxGroupSize: Int,
    val state: VideoGameState,
    val airdropScheduled: Boolean,
) {
    val id: GameId = GameId.fromGameIndex(index)
}

sealed interface VideoGameState {
    object Registration : VideoGameState
    object Shuffle : VideoGameState
    class InProgress(val playersCount: Int, val rounds: List<VideoGameRound>) : VideoGameState
    object Processing : VideoGameState
    object Missed : VideoGameState

    object Cancelling : VideoGameState

    object Broken : VideoGameState
}

sealed class VideoGameRegistrationStage {
    /**
     * User needs to first proof its credibility (by ensuring it has a deposit or invite)
     */
    class NeedsCredibilityProof(val requiredDeposit: ChainAssetWithAmount) : VideoGameRegistrationStage()

    /**
     * User can register to the game, either by obtaining credibility proof
     * (e.g. it has balance to pay deposit or has pending invite)
     * or by using his existing credibility
     */
    sealed class CanRegister : VideoGameRegistrationStage() {
        class WithCredibilityProof(
            val requiredDeposit: ChainAssetWithAmount,
            val cachedInvite: IssuedInvitation?,
        ) : CanRegister()

        class NoCredibilityProofRequired(
            val externallyRecognized: Boolean,
        ) : CanRegister()
    }

    /**
     * User has already registered to the upcoming game
     */
    object Registered : VideoGameRegistrationStage()
}

class VideoGameRound(val players: List<AccountId>, val roundIndex: Int)

fun VideoGameInfo.gameDuration() = (reportEnd - gameStartMillis).milliseconds

fun VideoGameRegistrationStage.registrationIsPossible() = this is VideoGameRegistrationStage.CanRegister || this is VideoGameRegistrationStage.NeedsCredibilityProof
