package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons.SignalBarsIcon
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons.SignalStrength
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun ConnectionStateBadge(
    modifier: Modifier = Modifier,
    state: PlayerConnectionState
) {
    val color = state.color()

    Row(
        modifier = modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        SignalBarsIcon(
            modifier = Modifier.size(BADGE_ICON_SIZE),
            strength = state.signalStrength(),
            color = color
        )
        NovaText(
            text = stringResource(state.labelRes()),
            style = NovaGameTypography.connectionBadgeLabel,
            color = color
        )
    }
}

@Composable
private fun PlayerConnectionState.color(): Color = when (this) {
    PlayerConnectionState.Connected -> GameColors.connectionConnected
    PlayerConnectionState.Connecting -> GameColors.connectionConnecting
    PlayerConnectionState.Disconnected,
    is PlayerConnectionState.Failed -> PolkadotTheme.colors.fg.tertiary
}

private fun PlayerConnectionState.labelRes(): Int = when (this) {
    PlayerConnectionState.Connected -> RCommon.string.video_game_connection_connected
    PlayerConnectionState.Connecting -> RCommon.string.video_game_connection_connecting
    PlayerConnectionState.Disconnected,
    is PlayerConnectionState.Failed -> RCommon.string.video_game_connection_not_connected
}

private fun PlayerConnectionState.signalStrength(): SignalStrength = when (this) {
    PlayerConnectionState.Connected -> SignalStrength.BEST
    PlayerConnectionState.Connecting -> SignalStrength.NORMAL
    PlayerConnectionState.Disconnected,
    is PlayerConnectionState.Failed -> SignalStrength.NO_SIGNAL
}

private val BADGE_ICON_SIZE = 32.dp
