package io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose.components

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun Header() {
    NovaText(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(
                top = 64.dp,
                bottom = PolkadotTheme.spacings.mediumIncreased
            ),
        text = stringResource(RCommon.string.video_game_vote_title),
        style = NovaGameTypography.votingHeader,
        color = GameColors.textOnGameBackground,
        textAlign = TextAlign.Center
    )
}
