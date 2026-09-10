package io.paritytech.polkadotapp.feature_videogame_impl.presentation.voting.compose.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import kotlin.math.ceil
import io.paritytech.polkadotapp.common.R as RCommon

private const val AutoConfirmDurationSeconds = 8
private const val MillisPerSecond = 1000
private const val FinalCountdownSecond = 1

@Composable
fun Footer(
    modifier: Modifier,
    onDone: () -> Unit,
    inProgress: Boolean,
    autoConfirm: Boolean
) {
    val progress = remember { Animatable(0f) }
    var consumed by rememberSaveable { mutableStateOf(false) }
    val secondsRemaining by remember {
        derivedStateOf {
            ceil((1f - progress.value) * AutoConfirmDurationSeconds).toInt().coerceAtLeast(FinalCountdownSecond)
        }
    }

    LaunchedEffect(inProgress, autoConfirm) {
        when {
            inProgress -> {
                consumed = true
                progress.snapTo(1f)
            }
            !autoConfirm -> {
                consumed = true
                progress.snapTo(0f)
            }
            consumed -> Unit
            else -> {
                progress.animateTo(
                    targetValue = 1f,
                    animationSpec = tween(
                        durationMillis = AutoConfirmDurationSeconds * MillisPerSecond,
                        easing = LinearEasing
                    )
                )
                consumed = true
                onDone()
            }
        }
    }

    Box(modifier = modifier) {
        ConfirmButton(
            modifier = Modifier
                .fillMaxWidth()
                .padding(
                    PaddingValues(
                        start = PolkadotTheme.spacings.large,
                        end = PolkadotTheme.spacings.large,
                        bottom = PolkadotTheme.spacings.mediumIncreased
                    )
                ),
            label = when {
                inProgress -> stringResource(RCommon.string.video_game_confirming)
                autoConfirm -> stringResource(RCommon.string.video_game_confirming_in, secondsRemaining)
                else -> stringResource(RCommon.string.common_confirm)
            },
            progress = { progress.value },
            enabled = inProgress.not(),
            onClick = onDone
        )
    }
}

@Composable
private fun ConfirmButton(
    modifier: Modifier,
    label: String,
    progress: () -> Float,
    enabled: Boolean,
    onClick: () -> Unit
) {
    val brush = rememberConfirmBrush()
    val interactionSource = remember { MutableInteractionSource() }

    Box(
        modifier = modifier
            .clip(PolkadotTheme.shapes.medium)
            .background(brush)
            .clickable(
                interactionSource = interactionSource,
                indication = ripple(color = GameColors.textOnGameBackground),
                enabled = enabled,
                role = Role.Button,
                onClick = onClick
            )
            .drawBehind {
                drawRect(
                    color = GameColors.confirmProgressFill,
                    size = Size(
                        width = size.width * progress().coerceIn(0f, 1f),
                        height = size.height
                    )
                )
            }
            .padding(vertical = PolkadotTheme.spacings.extraMedium),
        contentAlignment = Alignment.Center
    ) {
        NovaText(
            text = label,
            style = NovaGameTypography.confirmButton,
            color = GameColors.textOnGameBackground,
            textAlign = TextAlign.Center,
            maxLines = 1
        )
    }
}

@Composable
private fun rememberConfirmBrush(): Brush = remember {
    Brush.verticalGradient(
        colorStops = arrayOf(
            0f to GameColors.confirmGradientStart,
            0.52f to GameColors.confirmGradientMiddle,
            1f to GameColors.confirmGradientEnd
        )
    )
}
