package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonColors
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonShape
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButtonSize
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.HelpOutlined
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
fun HowToPlayButton(
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    PolkadotTextButton(
        text = stringResource(RCommon.string.video_game_how_to_play),
        onClick = onClick,
        modifier = modifier,
        style = HowToPlayButtonStyle,
        size = howToPlayButtonSize(),
        shape = PolkadotButtonShape.pill,
        iconEnd = NovaIcons.HelpOutlined
    )
}

private val HowToPlayButtonStyle = object : PolkadotButtonStyle {
    override val colors: PolkadotButtonColors = PolkadotButtonColors(
        containerBrush = SolidColor(GameColors.howToPlayBackground),
        contentColor = GameColors.howToPlayContent,
        disabledContainerBrush = SolidColor(GameColors.howToPlayBackground),
        disabledContentColor = GameColors.howToPlayContent,
    )
    override val rippleColor: Color = GameColors.howToPlayContent
}

@Composable
private fun howToPlayButtonSize(): PolkadotButtonSize {
    val padding = PaddingValues(
        start = PolkadotTheme.spacings.mediumIncreased,
        top = PolkadotTheme.spacings.small,
        end = PolkadotTheme.spacings.extraMedium,
        bottom = PolkadotTheme.spacings.small
    )
    val textStyle = PolkadotTheme.typography.title.medium
    return remember(padding, textStyle) { GameButtonSize(padding, textStyle) }
}

private data class GameButtonSize(
    override val padding: PaddingValues,
    override val textStyle: TextStyle
) : PolkadotButtonSize
