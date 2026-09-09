package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components.waitingRoom

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors

@Composable
fun WaitingRoomBackground(
    modifier: Modifier = Modifier,
    isVisible: Boolean = true,
) {
    if (isVisible) {
        ShimmeringBand(modifier)
    }
}

@Composable
private fun ShimmeringBand(modifier: Modifier) {
    val transition = rememberInfiniteTransition(label = "waitingRoomShimmer")
    val shimmerProgress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(SHIMMER_DURATION_MS, easing = LinearEasing),
            repeatMode = RepeatMode.Restart,
        ),
        label = "waitingRoomShimmerProgress",
    )

    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height

        fun y(refY: Float) = refY / REF_HEIGHT * h

        val bandPath = Path().apply {
            moveTo(w, y(BAND_TOP_RIGHT_Y))
            lineTo(w, y(BAND_BOTTOM_RIGHT_Y))
            lineTo(0f, y(BAND_BOTTOM_LEFT_Y))
            lineTo(0f, y(BAND_TOP_LEFT_Y))
            close()
        }
        val bandTop = y(BAND_TOP_RIGHT_Y)
        val bandBottom = y(BAND_BOTTOM_LEFT_Y)
        val bandBrush = Brush.verticalGradient(
            0.00f to GameColors.waitingRoomBandTop.copy(alpha = BAND_EDGE_ALPHA),
            BAND_SOLID_START to GameColors.waitingRoomBandTop,
            BAND_HIGHLIGHT_STOP to GameColors.waitingRoomBandHighlight,
            BAND_SHADE_STOP to GameColors.waitingRoomBandShade,
            BAND_SOLID_END to GameColors.waitingRoomBandBottom,
            1.00f to GameColors.waitingRoomBandBottom.copy(alpha = BAND_EDGE_ALPHA),
            startY = bandTop,
            endY = bandBottom,
        )
        drawPath(path = bandPath, brush = bandBrush)

        val shimmerWidth = w * SHIMMER_WIDTH_FRACTION
        val totalTravel = w + shimmerWidth * 2
        val shimmerStart = -shimmerWidth + shimmerProgress * totalTravel
        val shimmerEnd = shimmerStart + shimmerWidth

        val shimmerBrush = Brush.linearGradient(
            0f to GameColors.waitingRoomShimmerEdge,
            0.5f to GameColors.waitingRoomShimmerCore,
            1f to GameColors.waitingRoomShimmerEdge,
            start = Offset(shimmerStart, 0f),
            end = Offset(shimmerEnd, 0f),
        )
        drawPath(path = bandPath, brush = shimmerBrush)
    }
}

private const val REF_HEIGHT = 844f

/**
 * Band parallelogram vertices in the 844-unit-tall Figma reference frame;
 * rescaled to canvas height at draw time via the local `y()` function.
 */
private const val BAND_TOP_RIGHT_Y = 113f
private const val BAND_BOTTOM_RIGHT_Y = 475f
private const val BAND_TOP_LEFT_Y = 363f
private const val BAND_BOTTOM_LEFT_Y = 731f

// Slower, wider sweep reads as a soft light pass instead of a mechanical shimmer.
private const val SHIMMER_DURATION_MS = 4500
private const val SHIMMER_WIDTH_FRACTION = 0.7f

// Four-stop linear gradient matching the Figma source: dark navy at the top
// edge, brightest lavender highlight ~1/3 in, medium shade ~2/3 in, deep
// indigo at the bottom. Outer 0.5-alpha stops soften the parallelogram edges
// where the band meets the black background.
private const val BAND_EDGE_ALPHA = 0.5f
private const val BAND_SOLID_START = 0.08f
private const val BAND_HIGHLIGHT_STOP = 0.35f
private const val BAND_SHADE_STOP = 0.65f
private const val BAND_SOLID_END = 0.92f
