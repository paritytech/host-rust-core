package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun HostUnavailableTooltip(
    modifier: Modifier = Modifier,
    visible: Boolean
) {
    AnimatedVisibility(
        modifier = modifier,
        visible = visible,
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut()
    ) {
        VideoGameTooltip(
            imageVector = null,
            text = stringResource(RCommon.string.video_game_play_no_host_pill),
            shape = CircleShape
        )
    }
}
