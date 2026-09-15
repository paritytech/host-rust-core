package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components.waitingRoom

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.sp
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.design.colors.LegacyNovaStableColors
import io.paritytech.polkadotapp.design.components.text.NovaText
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.NovaGameTypography
import kotlin.time.Duration.Companion.seconds

@Composable
fun CountdownNumeral(
    modifier: Modifier = Modifier,
    secondsLeft: Long,
) {
    val targetColor = when {
        secondsLeft <= ALARM_SECONDS -> GameColors.countdownAlarm
        secondsLeft <= WARN_SECONDS -> LegacyNovaStableColors.AmberAmber500
        else -> GameColors.textOnGameBackground
    }
    val animatedColor by animateColorAsState(
        targetValue = targetColor,
        animationSpec = tween(COLOR_TWEEN_MS),
        label = "countdownColor",
    )

    val displayText = LocalTimeFormatter.current.formatCountdown(secondsLeft.seconds)

    NovaText(
        modifier = modifier,
        text = displayText,
        style = NovaGameTypography.countdown,
        color = animatedColor,
        maxLines = 1,
        softWrap = false,
        autoSize = CountdownAutoSize,
    )
}

private const val WARN_SECONDS = 10L
private const val ALARM_SECONDS = 5L
private const val COLOR_TWEEN_MS = 220

private val CountdownAutoSize = TextAutoSize.StepBased(
    minFontSize = 80.sp,
    maxFontSize = 164.sp,
    stepSize = 4.sp,
)
