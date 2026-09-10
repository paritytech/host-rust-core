package io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TileMode
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors

private const val BAND_TOP_RIGHT_Y_FRACTION = 0.134f
private const val BAND_TOP_LEFT_Y_FRACTION = 0.431f
private const val BAND_BOTTOM_RIGHT_Y_FRACTION = 0.557f
private const val BAND_BOTTOM_LEFT_Y_FRACTION = 0.866f
private const val GRADIENT_DARK_X_FRACTION = 0.68f

@Composable
fun DiagonalStripeBackground(
    modifier: Modifier = Modifier,
    isVisible: Boolean = true,
    isIntroAnimating: Boolean = false
) {
    val revealProgress = remember { Animatable(1f) }

    LaunchedEffect(isIntroAnimating) {
        if (isIntroAnimating) {
            revealProgress.snapTo(0f)
            revealProgress.animateTo(
                targetValue = 1f,
                animationSpec = tween(1500, easing = FastOutSlowInEasing)
            )
        } else {
            revealProgress.snapTo(1f)
        }
    }

    if (isVisible) {
        Box(
            modifier = modifier
                .fillMaxSize()
                .drawWithCache {
                    val w = size.width
                    val h = size.height

                    val path = Path().apply {
                        moveTo(0f, h * BAND_TOP_LEFT_Y_FRACTION)
                        lineTo(w, h * BAND_TOP_RIGHT_Y_FRACTION)
                        lineTo(w, h * BAND_BOTTOM_RIGHT_Y_FRACTION)
                        lineTo(0f, h * BAND_BOTTOM_LEFT_Y_FRACTION)
                        close()
                    }
                    val gradientBrush = Brush.horizontalGradient(
                        colors = listOf(
                            GameColors.waitingRoomBandBottom,
                            GameColors.diagonalBandGradientDark
                        ),
                        startX = 0f,
                        endX = w * GRADIENT_DARK_X_FRACTION,
                        tileMode = TileMode.Clamp
                    )

                    onDrawBehind {
                        val alpha = revealProgress.value
                        drawPath(path = path, color = GameColors.waitingRoomBandTop, alpha = alpha)
                        drawPath(path = path, brush = gradientBrush, alpha = alpha)
                    }
                }
        )
    }
}
