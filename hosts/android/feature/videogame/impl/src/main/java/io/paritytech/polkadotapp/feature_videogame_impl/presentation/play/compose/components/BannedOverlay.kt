package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.VisibilityOffOutlined
import io.paritytech.polkadotapp.design.components.spacer.VerticalSpacer
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun BannedOverlay() {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(PolkadotTheme.colors.bg.surface.nested),
        contentAlignment = Alignment.Center
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            NovaIcon(
                modifier = Modifier.size(32.dp),
                imageVector = NovaIcons.VisibilityOffOutlined,
                tint = PolkadotTheme.colors.fg.tertiary
            )

            VerticalSpacer { small }

            NovaText(
                text = stringResource(RCommon.string.video_game_play_player_banned),
                style = PolkadotTheme.typography.title.large,
                color = PolkadotTheme.colors.fg.tertiary
            )
        }
    }
}
