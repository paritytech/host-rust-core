package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation

import android.graphics.Bitmap
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageShader
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalDensity
import androidx.core.graphics.scale
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.random.Random

// Brush-based approximation of the holographic shader for API < 33 (no RuntimeShader): the same
// 20-stop foil ramp as a linear gradient slid by tilt, an additive perpendicular highlight, and a
// static tiled two-layer noise for grain. All colours and factors come from HolographicSpec
// (shared with the AGSL shader). Visual gap vs the shader: grain isn't luma-modulated, so its
// amplitude is fixed at the foil's average luma.

// The shader brightens/darkens by ±amplitude/2; the bright half is exact via BlendMode.Plus, the
// dark half is srcOver black bumped slightly to offset the multiplicative weakening
// (c * (1 - a) vs the shader's c - amplitude/2 at the foil's typical luma ~0.85).
private const val HIGHLIGHT_ALPHA = HOLO_HIGHLIGHT_AMPLITUDE / 2f
private const val HIGHLIGHT_DARK_ALPHA = HIGHLIGHT_ALPHA / 0.85f

// Grain amplitude at the foil's average luma (the shader modulates it per pixel).
private const val FOIL_AVERAGE_LUMA = 0.85f
private const val GRAIN_AMP = HOLO_GRAIN_BASE_AMP * (1f - HOLO_GRAIN_LUMA_FACTOR * FOIL_AVERAGE_LUMA)
private const val GRAIN_TEXTURE_SIZE = 64

private val HighlightBrightStops = arrayOf(
    0.0f to Color.White.copy(alpha = HIGHLIGHT_ALPHA),
    0.5f to Color.White.copy(alpha = 0f)
)

private val HighlightDarkStops = arrayOf(
    0.5f to Color.Black.copy(alpha = 0f),
    1.0f to Color.Black.copy(alpha = HIGHLIGHT_DARK_ALPHA)
)

@Composable
internal fun Modifier.holographicFallback(
    tiltState: State<TiltState>,
    lagged: Boolean
): Modifier {
    val density = LocalDensity.current.density
    val grain = remember(density) { cachedGrainBrushes(density) }

    return drawBehind {
        val tilt = tiltState.value
        val tiltX = if (lagged) tilt.delayedX else tilt.x
        val tiltY = if (lagged) tilt.delayedY else tilt.y

        drawRect(
            brush = axisGradient(
                colorStops = HoloRampStops,
                axis = HoloMainAxis,
                size = size,
                shift = tiltX * HOLO_RAMP_TILT_X - tiltY * HOLO_RAMP_TILT_Y
            )
        )

        val highlightShift = tiltY * HOLO_HIGHLIGHT_TILT_Y - tiltX * HOLO_HIGHLIGHT_TILT_X
        drawRect(
            brush = axisGradient(HighlightBrightStops, HoloPerpAxis, size, highlightShift),
            blendMode = BlendMode.Plus
        )
        drawRect(
            brush = axisGradient(HighlightDarkStops, HoloPerpAxis, size, highlightShift)
        )

        drawRect(brush = grain.bright, blendMode = BlendMode.Plus)
        drawRect(brush = grain.dark)
    }
}

// Builds a CSS-style linear gradient along `axis` spanning the box, translated so that a `shift` in
// the shader's normalised t-coordinate moves the colour band identically: t' = t + shift means the
// gradient slides by -shift of its full length along the axis.
internal fun axisGradient(
    colorStops: Array<Pair<Float, Color>>,
    axis: Offset,
    size: Size,
    shift: Float
): Brush {
    val centre = Offset(size.width * 0.5f, size.height * 0.5f)
    val halfSpan = 0.5f * (abs(axis.x) * size.width + abs(axis.y) * size.height)
    val translation = axis * (-shift * 2f * halfSpan)
    return Brush.linearGradient(
        colorStops = colorStops,
        start = centre - axis * halfSpan + translation,
        end = centre + axis * halfSpan + translation
    )
}

private data class GrainBrushes(val bright: ShaderBrush, val dark: ShaderBrush)

// Bitmap generation + scaling is not free on low-end devices and the result only depends on
// density, so it's cached process-wide instead of per composition (the foil is composed for the
// card background + wordmark in both the list and the details screens).
private var grainCache: Pair<Float, GrainBrushes>? = null

private fun cachedGrainBrushes(density: Float): GrainBrushes {
    grainCache?.let { (cachedDensity, brushes) ->
        if (cachedDensity == density) return brushes
    }
    return generateGrainBrushes(density).also { grainCache = density to it }
}

// Static monochrome speckle, tiled across the card. Bright specks are plus-composited (matching
// the shader's additive c + v; srcOver white is nearly invisible on a bright foil), dark specks
// srcOver. Cells are upscaled nearest-neighbour to the shader's cell size to stay crisp.
private fun generateGrainBrushes(density: Float): GrainBrushes {
    val random = Random(GRAIN_TEXTURE_SIZE)
    val bright = IntArray(GRAIN_TEXTURE_SIZE * GRAIN_TEXTURE_SIZE)
    val dark = IntArray(GRAIN_TEXTURE_SIZE * GRAIN_TEXTURE_SIZE)

    for (i in bright.indices) {
        val n = random.nextFloat() - HOLO_GRAIN_BIAS
        val alpha = (abs(n) * GRAIN_AMP * 255).roundToInt().coerceIn(0, 255)
        if (n > 0) {
            bright[i] = (alpha shl 24) or 0xFFFFFF
        } else {
            dark[i] = alpha shl 24
        }
    }

    val cellPx = (HOLO_GRAIN_CELL_DP * density).roundToInt().coerceAtLeast(1)
    return GrainBrushes(
        bright = bright.toTiledBrush(cellPx),
        dark = dark.toTiledBrush(cellPx)
    )
}

private fun IntArray.toTiledBrush(cellPx: Int): ShaderBrush {
    val base = Bitmap.createBitmap(this, GRAIN_TEXTURE_SIZE, GRAIN_TEXTURE_SIZE, Bitmap.Config.ARGB_8888)
    val scaled = base.scale(GRAIN_TEXTURE_SIZE * cellPx, GRAIN_TEXTURE_SIZE * cellPx, filter = false)
    return ShaderBrush(ImageShader(scaled.asImageBitmap(), TileMode.Repeated, TileMode.Repeated))
}
