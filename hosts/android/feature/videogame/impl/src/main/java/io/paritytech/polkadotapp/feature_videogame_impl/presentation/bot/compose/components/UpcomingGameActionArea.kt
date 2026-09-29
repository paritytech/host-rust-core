package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.compose.components

import androidx.compose.foundation.border
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonColors
import io.paritytech.polkadotapp.design.components.button.common.PolkadotButtonStyle
import io.paritytech.polkadotapp.design.components.button.default.PolkadotButton
import io.paritytech.polkadotapp.design.components.button.default.PolkadotTextButton
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.models.VideoGameActionNew
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.theme.NovaPrizesColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import io.paritytech.polkadotapp.common.R as RCommon

@Composable
internal fun ActionArea(
    action: VideoGameActionNew,
    onRegister: () -> Unit,
    onStartPlaying: () -> Unit,
    onAddToCalendar: () -> Unit,
) {
    when (action) {
        is VideoGameActionNew.Register -> {
            PolkadotButton(
                modifier = Modifier
                    .fillMaxWidth()
                    .shadow(
                        elevation = REGISTER_CTA_GLOW_ELEVATION,
                        shape = CTA_SHAPE,
                        ambientColor = NovaPrizesColors.registerCtaGlow,
                        spotColor = NovaPrizesColors.registerCtaGlow,
                    ),
                onClick = onRegister,
                enabled = action.isAvailable,
                loading = action.inProgress,
                style = registerCtaStyle(),
            ) {
                val labelRes = if (action.openingSoon) {
                    RCommon.string.chat_bot_weekly_game_state_register_opening_soon
                } else {
                    RCommon.string.chat_bot_weekly_game_state_register_action
                }
                NovaText(
                    text = stringResource(labelRes),
                    color = NovaPrizesColors.textPrimary,
                    style = NovaGameTypography.confirmButton,
                )
            }
        }

        is VideoGameActionNew.AddToCalendar -> {
            if (!action.hideAddToCalendarButton) {
                val isEnabled = !action.isGameAddedToCalendar
                val label = if (action.isGameAddedToCalendar) {
                    stringResource(RCommon.string.chat_bot_weekly_game_add_to_calendar_action_added)
                } else {
                    stringResource(RCommon.string.chat_bot_weekly_game_add_to_calendar_action)
                }
                val buttonModifier = if (isEnabled) {
                    Modifier
                        .fillMaxWidth()
                        .shadow(
                            elevation = ADD_TO_CALENDAR_CTA_GLOW_ELEVATION,
                            shape = CTA_SHAPE,
                            ambientColor = NovaPrizesColors.addToCalendarCtaGlow,
                            spotColor = NovaPrizesColors.addToCalendarCtaGlow,
                        )
                } else {
                    Modifier
                        .fillMaxWidth()
                        .border(
                            width = PolkadotTheme.borders.default,
                            color = NovaPrizesColors.disabledCtaBorder,
                            shape = CTA_SHAPE,
                        )
                }
                PolkadotButton(
                    modifier = buttonModifier,
                    onClick = onAddToCalendar,
                    style = addToCalendarCtaStyle(),
                    enabled = isEnabled,
                ) {
                    NovaText(
                        text = label,
                        color = NovaPrizesColors.textPrimary,
                        style = NovaGameTypography.confirmButton,
                    )
                }
            }
        }

        is VideoGameActionNew.StartPlaying -> {
            PolkadotTextButton(
                text = stringResource(RCommon.string.chat_bot_weekly_game_start_playing_action),
                onClick = onStartPlaying,
                modifier = Modifier.fillMaxWidth(),
                style = PolkadotButtonStyle.primary(),
            )
        }
    }
}

@Composable
private fun registerCtaStyle(): PolkadotButtonStyle {
    val content = NovaPrizesColors.textPrimary
    val colors = PolkadotButtonColors(
        containerBrush = RegisterCtaGradient,
        contentColor = content,
        disabledContainerBrush = RegisterCtaDisabledBrush,
        disabledContentColor = NovaPrizesColors.registerCtaDisabledContent,
    )
    return remember(colors, content) {
        object : PolkadotButtonStyle {
            override val colors = colors
            override val rippleColor = content
        }
    }
}

private val REGISTER_CTA_GLOW_ELEVATION = 16.dp
private val ADD_TO_CALENDAR_CTA_GLOW_ELEVATION = 4.dp
private val CTA_SHAPE = RoundedCornerShape(16.dp)

private val RegisterCtaGradient: Brush = Brush.verticalGradient(
    0.00f to NovaPrizesColors.registerCtaTopBlue,
    0.52f to NovaPrizesColors.registerCtaMidBlue,
    1.00f to NovaPrizesColors.registerCtaBottomPurple,
)

private val RegisterCtaDisabledBrush: Brush = SolidColor(NovaPrizesColors.registerCtaDisabled)

@Composable
private fun addToCalendarCtaStyle(): PolkadotButtonStyle {
    val content = NovaPrizesColors.textPrimary
    val colors = PolkadotButtonColors(
        containerBrush = AddToCalendarGradient,
        contentColor = content,
        disabledContainerBrush = AddToCalendarDisabledBrush,
        disabledContentColor = NovaPrizesColors.addToCalendarCtaDisabledContent,
    )
    return remember(colors, content) {
        object : PolkadotButtonStyle {
            override val colors = colors
            override val rippleColor = content
        }
    }
}

private val AddToCalendarGradient: Brush = Brush.verticalGradient(
    0.00f to NovaPrizesColors.addToCalendarCtaTop,
    0.52f to NovaPrizesColors.addToCalendarCtaMid,
    1.00f to NovaPrizesColors.addToCalendarCtaBottom,
)

private val AddToCalendarDisabledBrush: Brush = SolidColor(NovaPrizesColors.addToCalendarCtaDisabled)
