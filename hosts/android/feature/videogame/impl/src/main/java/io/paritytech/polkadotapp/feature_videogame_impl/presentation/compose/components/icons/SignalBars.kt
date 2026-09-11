package io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.icons

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap

internal enum class SignalStrength {
    NO_SIGNAL,
    WEAK,
    NORMAL,
    GOOD,
    BEST
}

@Composable
internal fun SignalBarsIcon(
    modifier: Modifier,
    strength: SignalStrength,
    color: Color,
) {
    val dimColor = remember(color) { color.copy(alpha = UNLIT_ALPHA) }
    val litBars = strength.litBars

    Canvas(modifier = modifier) {
        val scale = size.minDimension / VIEWPORT
        val strokeWidth = STROKE_WIDTH * scale
        val baselineY = BASELINE_Y * scale

        // A circle rather than a zero-length round-cap line: some GPU canvas backends
        // drop zero-length segments instead of drawing the cap.
        drawCircle(
            color = color,
            radius = strokeWidth / 2,
            center = Offset(DOT_X * scale, baselineY),
        )

        BAR_TOPS_Y.forEachIndexed { index, topY ->
            val x = (FIRST_BAR_X + index * BAR_SPACING) * scale
            drawLine(
                color = if (index < litBars) color else dimColor,
                start = Offset(x, baselineY),
                end = Offset(x, topY * scale),
                strokeWidth = strokeWidth,
                cap = StrokeCap.Round,
            )
        }
    }
}

private val SignalStrength.litBars: Int
    get() = when (this) {
        SignalStrength.NO_SIGNAL -> 0
        SignalStrength.WEAK -> 1
        SignalStrength.NORMAL -> 2
        SignalStrength.GOOD -> 3
        SignalStrength.BEST -> 4
    }

private const val VIEWPORT = 32f
private const val STROKE_WIDTH = 2f
private const val BASELINE_Y = 21.3334f
private const val DOT_X = 9.3368f
private const val FIRST_BAR_X = 12.6668f
private const val BAR_SPACING = 3.3334f
private val BAR_TOPS_Y = floatArrayOf(18.6667f, 16f, 13.3334f, 10.6667f)
private const val UNLIT_ALPHA = 0.3f
