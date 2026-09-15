package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun HostingHeader(
    modifier: Modifier,
    isCurrentPlayerHost: Boolean
) {
    Box(modifier) {
        NovaText(
            modifier = Modifier.fillMaxWidth(),
            text = stringResource(
                if (isCurrentPlayerHost) {
                    RCommon.string.video_game_play_player_you_are_host
                } else {
                    RCommon.string.video_game_play_player_meet_host
                }
            ),
            style = NovaGameTypography.hostIntroduction,
            color = GameColors.textOnGameBackground,
            textAlign = TextAlign.Center,
            maxLines = 1
        )
    }
}

@Composable
fun HostingFooter(
    modifier: Modifier,
    isCurrentPlayerHost: Boolean
) {
    Box(modifier) {
        NovaText(
            modifier = Modifier.fillMaxWidth(),
            text = stringResource(
                if (isCurrentPlayerHost) {
                    RCommon.string.video_game_play_host_transition_description_show
                } else {
                    RCommon.string.video_game_play_host_transition_description_copy
                }
            ),
            style = NovaGameTypography.hostIntroduction,
            color = GameColors.textOnGameBackground,
            textAlign = TextAlign.Center,
            maxLines = 1
        )
    }
}
