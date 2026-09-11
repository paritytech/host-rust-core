package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameUiState
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun ConnectingCountdown(
    modifier: Modifier,
    state: VideoGameUiState,
) {
    Box(modifier) {
        if (state is VideoGameUiState.Connecting) {
            NovaText(
                text = stringResource(
                    RCommon.string.video_game_connection_game_starting_in,
                    state.timeLeft.inWholeSeconds
                ),
                style = NovaGameTypography.connectingCountdown,
                color = GameColors.textOnGameBackground
            )
        }
    }
}
