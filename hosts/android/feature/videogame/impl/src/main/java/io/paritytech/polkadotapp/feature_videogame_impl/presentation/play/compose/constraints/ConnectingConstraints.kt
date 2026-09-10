package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.constraints

import androidx.constraintlayout.compose.ConstrainedLayoutReference
import androidx.constraintlayout.compose.ConstraintSetScope
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import kotlinx.collections.immutable.ImmutableList

fun ConstraintSetScope.createConnectingConstraints(
    players: ImmutableList<PlayerUiModel>,
    anchorLeft: ConstrainedLayoutReference,
    anchorRight: ConstrainedLayoutReference,
    camerasRevealed: Boolean,
) {
    createPlayersGridConstraints(players, anchorLeft, anchorRight)

    hideHostingIntroductionInfo()
    hideHostingProgressBar()

    if (camerasRevealed) {
        hideHowToPlayButton()
    } else {
        showHowToPlayButton()
    }

    showConnectingCountdown()
}
