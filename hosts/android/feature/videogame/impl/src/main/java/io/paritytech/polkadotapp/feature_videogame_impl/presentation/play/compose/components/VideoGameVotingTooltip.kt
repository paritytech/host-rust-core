package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.animation.AnimatedContent
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons.TouchGesture
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.tooltipTransition
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun VideoGameVotingTooltip(
    modifier: Modifier = Modifier,
    visible: Boolean
) {
    AnimatedContent(
        modifier = modifier,
        targetState = visible,
        transitionSpec = tooltipTransition(),
        contentAlignment = Alignment.Center
    ) { isVisible ->
        if (isVisible) {
            VideoGameTooltip(
                imageVector = NovaIcons.TouchGesture,
                text = stringResource(RCommon.string.video_game_tips_vote)
            )
        }
    }
}
