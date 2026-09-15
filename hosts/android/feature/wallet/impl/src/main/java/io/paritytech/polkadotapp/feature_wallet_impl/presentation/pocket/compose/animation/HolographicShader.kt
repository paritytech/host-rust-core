package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import kotlin.math.roundToInt
import kotlin.random.Random

// Aa 20-stop foil colour ramp along a 151.367° axis, a perpendicular zero-mean luminance highlight,
// and monochrome film grain.
// The `tilt` uniform slides the ramp and highlight so the foil reacts to how the device is held.
// `density` converts the grain cell size.
// All colours and factors are templated in from HolographicSpec (shared with the API < 33 Brush
// fallback). AGSL forbids array initializers, so the Metal pos[]/col[] tables become a generated
// chain of clamped mixes (same piecewise-linear result).
private val HOLOGRAPHIC_GRADIENT_AGSL = """
uniform float2 size;
uniform float2 tilt;
uniform float seed;
uniform float density;

// Per-segment interpolation factor of the ramp.
float seg(float t, float a, float b) {
    return clamp((t - a) / (b - a), 0.0, 1.0);
}

half3 rampColor(float t) {
${rampChainAgsl()}
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

half4 main(float2 position) {
    float2 centre = size * 0.5;

    // Main gradient axis: 151.367deg (screen space, y-down).
    const float2 dir  = float2(${HoloMainAxis.x}, ${HoloMainAxis.y});
    // Perpendicular axis (points down-left); s=0 is the top-right side.
    const float2 perp = float2(${HoloPerpAxis.x}, ${HoloPerpAxis.y});

    // Position along the main axis, normalised 0...1 across the box (CSS-style).
    float halfMain = 0.5 * (abs(dir.x) * size.x + abs(dir.y) * size.y);
    float t = 0.5 + dot(position - centre, dir) / (2.0 * halfMain);
    // Tilt slides the colour band along the axis.
    t += tilt.x * $HOLO_RAMP_TILT_X - tilt.y * $HOLO_RAMP_TILT_Y;
    t = clamp(t, 0.0, 1.0);

    half3 base = rampColor(t);

    // Position along the perpendicular axis, normalised 0...1.
    float halfPerp = 0.5 * (abs(perp.x) * size.x + abs(perp.y) * size.y);
    float s = 0.5 + dot(position - centre, perp) / (2.0 * halfPerp);
    // Zero-mean luminance highlight: top-right brighter, bottom-left darker.
    // It also drifts with tilt so the sheen travels across the card.
    float sShift = s + tilt.y * $HOLO_HIGHLIGHT_TILT_Y - tilt.x * $HOLO_HIGHLIGHT_TILT_X;
    float perpHighlight = (0.5 - sShift) * $HOLO_HIGHLIGHT_AMPLITUDE;
    base = clamp(base + half3(half(perpHighlight)), half3(0.0), half3(1.0));

    // Monochrome film grain: crisp per-cell speckle, stronger on mid-tones
    // and fading on the whites. Cells are slightly sub-point so the speckle
    // reads finer, the amplitude is light, and it leans bright (lighter
    // specks rather than dark) by biasing the noise above zero.
    float n = hash21(floor(position / ($HOLO_GRAIN_CELL_DP * density)) + seed) - $HOLO_GRAIN_BIAS;
    float luma = dot(base, half3(0.2126, 0.7152, 0.0722));
    float grainAmp = $HOLO_GRAIN_BASE_AMP * (1.0 - $HOLO_GRAIN_LUMA_FACTOR * float(luma));
    base = clamp(base + half3(half(n * grainAmp)), half3(0.0), half3(1.0));

    return half4(base, 1.0);
}
"""

private fun rampChainAgsl(): String = buildString {
    appendLine("    half3 c = ${HoloRampStops.first().second.toAgslHalf3()};")
    HoloRampStops.toList().zipWithNext().forEach { (from, to) ->
        appendLine("    c = mix(c, ${to.second.toAgslHalf3()}, half(seg(t, ${from.first}, ${to.first})));")
    }
    append("    return c;")
}

private fun Color.toAgslHalf3(): String {
    val r = (red * 255).roundToInt()
    val g = (green * 255).roundToInt()
    val b = (blue * 255).roundToInt()
    return "half3($r.0, $g.0, $b.0) / 255.0"
}

private const val SEED_RANGE = 100f

// Fills the drawing area with the gyroscope-driven holographic shader. The tilt State is read inside
// the draw lambda so per-frame sensor updates invalidate the draw phase only, never recomposition.
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
@Composable
internal fun Modifier.holographicShader(
    tiltState: State<TiltState>,
    lagged: Boolean
): Modifier {
    val shader = remember { RuntimeShader(HOLOGRAPHIC_GRADIENT_AGSL) }
    val brush = remember(shader) { ShaderBrush(shader) }
    val seed = remember { Random.nextFloat() * SEED_RANGE }

    return drawWithCache {
        shader.setFloatUniform("size", size.width, size.height)
        shader.setFloatUniform("seed", seed)
        shader.setFloatUniform("density", density)
        onDrawBehind {
            val tilt = tiltState.value
            if (lagged) {
                shader.setFloatUniform("tilt", tilt.delayedX, tilt.delayedY)
            } else {
                shader.setFloatUniform("tilt", tilt.x, tilt.y)
            }
            drawRect(brush)
        }
    }
}
