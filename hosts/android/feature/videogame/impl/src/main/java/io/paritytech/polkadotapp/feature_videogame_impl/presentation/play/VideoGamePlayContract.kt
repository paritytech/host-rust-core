package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameStages
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGamePlayUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameTutorialState
import kotlinx.collections.immutable.ImmutableSet
import kotlinx.coroutines.flow.StateFlow

interface VideoGamePlayContract {
    val gameRenderState: StateFlow<VideoGamePlayUiState>
    val stages: StateFlow<VideoGameStages>
    val selections: StateFlow<ImmutableSet<AccountId>>

    /** Sugar level (0f–1f) driving confetti intensity, based on acceptance count. */
    val sugarLevel: StateFlow<Float>

    val votingTooltipVisible: StateFlow<Boolean>
    val noHostTooltipVisible: StateFlow<Boolean>
    val tutorialState: StateFlow<VideoGameTutorialState>

    fun collapse()
    fun showTutorial()
    fun hideTutorial()
    fun selectPlayer(player: PlayerUiModel)
    fun banPlayer(accountId: AccountId)
    fun unbanPlayer(accountId: AccountId)
}
