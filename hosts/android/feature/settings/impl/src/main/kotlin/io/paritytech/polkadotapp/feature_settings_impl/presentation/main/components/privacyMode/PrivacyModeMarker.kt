package io.paritytech.polkadotapp.feature_settings_impl.presentation.main.components.privacyMode

import android.graphics.BlurMaskFilter
import android.graphics.Paint
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asAndroidPath
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp

// The pointer under a mode, tying its circle to its label. The selected one is larger and glows in the mode's
// own accent, which is what carries the selection down into the labels.
@Composable
internal fun ModeMarker(
    modifier: Modifier,
    appearance: ModeAppearance,
    isSelected: Boolean
) {
    val selection by animateFloatAsState(
        targetValue = if (isSelected) 1f else 0f,
        animationSpec = SELECTION_ANIMATION,
        label = "markerSelection"
    )

    val color = appearance.markerColor(selection)
    val side = lerp(MARKER_SIZE, SELECTED_MARKER_SIZE, selection)

    Spacer(
        // The caller's modifier carries the offset that puts this marker under its mode, so it has to sit
        // before the drawing: a draw modifier paints at the node's own position, ignoring a later shift.
        modifier = Modifier
            .size(MARKER_BOX_SIZE)
            .then(modifier)
            .drawWithCache {
                // An upward triangle inscribed in a square of `side`, centred in the box.
                val half = side.toPx() / 2f
                val centreX = size.width / 2f
                val centreY = size.height / 2f
                val triangle = Path().apply {
                    moveTo(centreX, centreY - half)
                    lineTo(centreX + half, centreY + half)
                    lineTo(centreX - half, centreY + half)
                    close()
                }
                val androidTriangle = triangle.asAndroidPath()

                val glowPaint = Paint().apply {
                    isAntiAlias = true
                    this.color = color.copy(alpha = selection * GLOW_ALPHA).toArgb()
                    maskFilter = BlurMaskFilter(MARKER_GLOW_BLUR.toPx(), BlurMaskFilter.Blur.NORMAL)
                }

                onDrawBehind {
                    if (selection > 0f) {
                        drawIntoCanvas { canvas -> canvas.nativeCanvas.drawPath(androidTriangle, glowPaint) }
                    }

                    drawPath(triangle, color = color)
                }
            }
    )
}

private val MARKER_SIZE = 8.dp
private val SELECTED_MARKER_SIZE = 12.dp

private val MARKER_GLOW_BLUR = 8.dp

internal val MARKER_BOX_SIZE = SELECTED_MARKER_SIZE + MARKER_GLOW_BLUR * 2
