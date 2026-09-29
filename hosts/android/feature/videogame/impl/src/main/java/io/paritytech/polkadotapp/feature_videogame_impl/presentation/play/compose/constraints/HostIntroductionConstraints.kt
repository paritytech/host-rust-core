package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.constraints

import androidx.compose.ui.unit.dp
import androidx.constraintlayout.compose.ConstraintSetScope
import androidx.constraintlayout.compose.Dimension
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.referenceId
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.sortResult
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import kotlinx.collections.immutable.ImmutableList

fun ConstraintSetScope.createHostIntroductionConstraints(
    players: ImmutableList<PlayerUiModel>,
) {
    players
        .sortedBy { it.sortResult }
        .forEachIndexed { index, player ->
            val ref = createRefFor(player.referenceId)

            if (player.isHost) {
                constrain(ref) {
                    width = Dimension.fillToConstraints
                    height = Dimension.ratio("1:1")

                    start.linkTo(parent.start, margin = 32.dp)
                    end.linkTo(parent.end, margin = 32.dp)
                    top.linkTo(parent.top)
                    bottom.linkTo(parent.bottom)
                }

                showHostingIntroductionInfo(ref)
            } else {
                constrain(ref) {
                    width = Dimension.percent(0.4f)
                    height = Dimension.ratio("1:1")

                    linkOutOfScreenByIndex(index)
                }
            }
        }

    hideHostingProgressBar()
    hideHowToPlayButton()
    hideConnectingCountdown()
}
