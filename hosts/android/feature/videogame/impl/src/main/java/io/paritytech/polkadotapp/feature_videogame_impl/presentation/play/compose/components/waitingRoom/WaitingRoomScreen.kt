package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components.waitingRoom

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.ArrowDropdown
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameUiState
import kotlin.time.Duration
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun WaitingRoomScreen(
    modifier: Modifier = Modifier,
    state: VideoGameUiState.WaitingRoom,
    onCollapse: () -> Unit,
    onOpenTutorial: () -> Unit,
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(Color.Black),
    ) {
        WaitingRoomBackground(modifier = Modifier.fillMaxSize())

        BottomBlackFade(modifier = Modifier.align(Alignment.BottomCenter))

        Box(
            modifier = Modifier
                .align(Alignment.TopStart)
                .statusBarsPadding()
                .padding(
                    horizontal = PolkadotTheme.spacings.large,
                    vertical = PolkadotTheme.spacings.small,
                )
                .wrapContentSize(),
        ) {
            CloseButton(onClick = onCollapse)
        }

        Column(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .padding(horizontal = PolkadotTheme.spacings.large),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
        ) {
            NovaText(
                text = stringResource(RCommon.string.video_game_pill_waiting_countdown_label),
                style = NovaGameTypography.waitingRoomHeadline,
                color = GameColors.textOnGameBackground,
            )
            CountdownNumeral(secondsLeft = state.timeLeft.inWholeSeconds)
        }

        HowToPlayButton(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(PolkadotTheme.spacings.extraMedium)
                .navigationBarsPadding(),
            onClick = onOpenTutorial,
        )
    }
}

@Composable
private fun CloseButton(onClick: () -> Unit) {
    PolkadotSurface(
        modifier = Modifier.size(CLOSE_BUTTON_SIZE),
        shape = CircleShape,
        color = Color.White.copy(alpha = CLOSE_BUTTON_BG_ALPHA),
        contentColor = Color.White,
        onClick = onClick,
        contentAlignment = Alignment.Center,
    ) {
        NovaIcon(
            modifier = Modifier.size(CLOSE_BUTTON_ICON_SIZE),
            imageVector = NovaIcons.ArrowDropdown,
        )
    }
}

@Composable
private fun HowToPlayButton(
    modifier: Modifier,
    onClick: () -> Unit,
) {
    PolkadotSurface(
        modifier = modifier
            .fillMaxWidth()
            .height(CTA_HEIGHT)
            .shadow(
                elevation = CTA_GLOW_ELEVATION,
                shape = RoundedCornerShape(CTA_RADIUS),
                ambientColor = Color.White.copy(alpha = CTA_GLOW_ALPHA),
                spotColor = Color.White.copy(alpha = CTA_GLOW_ALPHA),
            ),
        shape = RoundedCornerShape(CTA_RADIUS),
        color = GameColors.waitingRoomCtaBackground,
        border = BorderStroke(CTA_BORDER_WIDTH, Color.White.copy(alpha = CTA_BORDER_ALPHA)),
        contentColor = Color.White.copy(alpha = CTA_TEXT_ALPHA),
        onClick = onClick,
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier.fillMaxSize(),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            NovaText(
                text = stringResource(RCommon.string.video_game_how_to_play),
                style = NovaGameTypography.howToPlay,
                color = Color.White.copy(alpha = CTA_TEXT_ALPHA),
            )
        }
    }
}

@Composable
private fun BottomBlackFade(modifier: Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(BOTTOM_FADE_HEIGHT)
            .background(
                remember {
                    Brush.verticalGradient(
                        colors = listOf(Color.Transparent, Color.Black),
                    )
                },
            ),
    )
}

private val CLOSE_BUTTON_SIZE = 40.dp
private val CLOSE_BUTTON_ICON_SIZE = 24.dp
private const val CLOSE_BUTTON_BG_ALPHA = 0.12f

private val CTA_HEIGHT = 56.dp
private val CTA_RADIUS = 16.dp
private val CTA_BORDER_WIDTH = 1.dp
private val CTA_GLOW_ELEVATION = 4.dp
private const val CTA_BORDER_ALPHA = 0.12f
private const val CTA_TEXT_ALPHA = 0.69f
private const val CTA_GLOW_ALPHA = 0.32f

private val BOTTOM_FADE_HEIGHT = 99.dp

@Preview
@Composable
private fun WaitingRoomScreenPreview() {
    PolkadotTheme {
        CompositionLocalProvider(LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current)) {
            WaitingRoomScreen(
                state = VideoGameUiState.WaitingRoom(Duration.parse("59s")),
                onCollapse = {},
                onOpenTutorial = {},
            )
        }
    }
}
