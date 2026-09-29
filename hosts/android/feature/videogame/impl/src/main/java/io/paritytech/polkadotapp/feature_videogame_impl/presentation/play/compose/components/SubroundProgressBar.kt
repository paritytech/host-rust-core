package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors

private val BAR_MAX_WIDTH = 16.dp
private val BAR_HEIGHT = 56.dp
private val BAR_CORNER_RADIUS = 24.dp
private val BAR_SHAPE = RoundedCornerShape(BAR_CORNER_RADIUS)

@Composable
fun SubroundProgressBar(
    modifier: Modifier = Modifier,
    currentSubround: Int,
    totalSubrounds: Int,
    subroundProgress: Float
) {
    Row(
        modifier = modifier,
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        for (i in 0 until totalSubrounds) {
            key(i) {
                val fillFraction = when {
                    i < currentSubround -> 1f
                    i == currentSubround -> subroundProgress.coerceIn(0f, 1f)
                    else -> 0f
                }

                val animatedFill by animateFloatAsState(
                    targetValue = fillFraction,
                    animationSpec = tween(1000, easing = LinearEasing),
                    label = "subroundFill_$i"
                )

                SubroundSegment(
                    modifier = Modifier
                        .width(BAR_MAX_WIDTH)
                        .height(BAR_HEIGHT)
                        .clip(BAR_SHAPE),
                    fillFraction = animatedFill
                )
            }
        }
    }
}

@Composable
private fun SubroundSegment(
    modifier: Modifier,
    fillFraction: Float
) {
    Box(
        modifier = modifier.drawWithCache {
            val cornerRadius = CornerRadius(BAR_CORNER_RADIUS.toPx(), BAR_CORNER_RADIUS.toPx())

            onDrawBehind {
                drawRoundRect(
                    color = GameColors.progressTrack,
                    topLeft = Offset.Zero,
                    size = size,
                    cornerRadius = cornerRadius
                )

                if (fillFraction > 0f) {
                    val fillHeight = size.height * fillFraction
                    drawRoundRect(
                        color = GameColors.progressFill,
                        topLeft = Offset(0f, size.height - fillHeight),
                        size = Size(size.width, fillHeight),
                        cornerRadius = cornerRadius
                    )
                }
            }
        }
    )
}
