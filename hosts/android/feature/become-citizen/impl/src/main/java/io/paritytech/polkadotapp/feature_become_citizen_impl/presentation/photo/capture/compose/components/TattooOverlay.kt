package io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.compose.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.ScrollableDefaults
import androidx.compose.foundation.gestures.rememberScrollableState
import androidx.compose.foundation.gestures.scrollable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.image.NovaAsyncImage
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_become_citizen_impl.presentation.photo.capture.models.TattooOverlayUiState
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.roundToInt

@Composable
fun TattooOverlay(
    modifier: Modifier,
    state: TattooOverlayUiState
) {
    var rotation by remember { mutableFloatStateOf(0f) }

    AnimatedVisibility(
        modifier = modifier,
        visible = state.isVisible && state.tattooImage != null,
        enter = fadeIn(),
        exit = fadeOut()
    ) {
        Box(
            modifier = Modifier.fillMaxSize()
        ) {
            state.tattooImage?.let { image ->
                NovaAsyncImage(
                    modifier = Modifier
                        .size(148.dp)
                        .rotate(rotation)
                        .align(Alignment.Center),
                    model = image.loadable,
                    contentScale = ContentScale.Crop
                )
            }

            RorationRuler(
                onRotationChanged = { rotation = it }
            )
        }
    }
}

@Composable
private fun BoxScope.RorationRuler(
    onRotationChanged: (Float) -> Unit
) {
    var offset by remember { mutableFloatStateOf(0f) }
    val haptic = LocalHapticFeedback.current
    var canvasWidth by remember { mutableStateOf(0f) }
    var previousTickIndex by remember { mutableIntStateOf(0) }

    val tickSpacingPx = if (canvasWidth > 0f) canvasWidth / 36f else 0f

    val scrollableState = rememberScrollableState { delta ->
        offset += delta
        onRotationChanged(offset / 5f)

        if (tickSpacingPx > 0f) {
            val currentTickIndex = (offset / tickSpacingPx).roundToInt()
            if (currentTickIndex != previousTickIndex) {
                haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
                previousTickIndex = currentTickIndex
            }
        }

        delta
    }

    val lineColor = PolkadotTheme.colors.fg.primary
    val tickColor = PolkadotTheme.colors.fg.secondary

    Canvas(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .height(56.dp)
            .onSizeChanged {
                canvasWidth = it.width.toFloat()
            }
            .scrollable(
                orientation = Orientation.Horizontal,
                state = scrollableState,
                flingBehavior = ScrollableDefaults.flingBehavior()
            )
            .align(Alignment.BottomCenter)
    ) {
        val width = size.width
        val height = size.height

        drawRuler(offset, width, height, tickSpacingPx, tickColor, lineColor)

        drawLine(
            color = lineColor,
            start = Offset(x = width / 2, y = height / 2 - 12.dp.toPx()),
            end = Offset(x = width / 2, y = height / 2 + 12.dp.toPx()),
            strokeWidth = 2.dp.toPx(),
            cap = StrokeCap.Round
        )
    }
}

private fun DrawScope.drawRuler(
    offset: Float,
    width: Float,
    height: Float,
    tickSpacing: Float,
    tickColor: Color,
    lineColor: Color
) {
    if (tickSpacing <= 0f) return

    val smallTickWidth = 1.dp.toPx()
    val mediumTickWidth = 2.dp.toPx()
    val mediumTickMultiplier = 9
    val smallTickHeight = 8.dp.toPx()
    val mediumTickHeight = 12.dp.toPx()
    val maxZoomHeight = 16.dp.toPx()

    val zoomZoneWidth = 24.dp.toPx()

    val tickCount = (width / tickSpacing).roundToInt()
    val startTick = ((-width / 2 - offset) / tickSpacing).roundToInt()
    val center = width / 2

    for (i in 0..tickCount) {
        val currentTick = startTick + i
        val tickX = center + (currentTick * tickSpacing) + offset

        if (tickX < 0 || tickX > width) {
            continue
        }

        val isMediumTick = currentTick % mediumTickMultiplier == 0
        val baseTickHeight = if (isMediumTick) mediumTickHeight else smallTickHeight
        val color = if (isMediumTick) lineColor else tickColor
        val strokeWidth = if (isMediumTick) mediumTickWidth else smallTickWidth

        val distanceFromCenter = abs(tickX - center)
        val finalTickHeight = if (distanceFromCenter < zoomZoneWidth) {
            val normalizedDistance = distanceFromCenter / zoomZoneWidth
            val scale = (cos(normalizedDistance * PI) + 1) / 2
            baseTickHeight + (maxZoomHeight - baseTickHeight) * scale.toFloat()
        } else {
            baseTickHeight
        }

        val startY = height / 2 - finalTickHeight / 2
        val endY = height / 2 + finalTickHeight / 2

        drawLine(
            color = color,
            start = Offset(x = tickX, y = startY),
            end = Offset(x = tickX, y = endY),
            strokeWidth = strokeWidth
        )
    }
}
