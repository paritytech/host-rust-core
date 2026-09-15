package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color

// Single source of truth for the holographic foil look.
// Consumed by both renderers: the AGSL shader (API 33+, source templated from these values) and
// the Brush fallback (API < 33).

// The 20-stop foil ramp, sampled from the Figma "Pocket" card gradient.
internal val HoloRampStops = arrayOf(
    0.00f to Color(0xFF8D8E8E),
    0.06f to Color(0xFFA5A5A6),
    0.11f to Color(0xFFB2B3B3),
    0.16f to Color(0xFFBFBFC0),
    0.21f to Color(0xFFCBCBCD),
    0.26f to Color(0xFFD6D7D9),
    0.31f to Color(0xFFDBDCDE),
    0.41f to Color(0xFFDCDEE0), // silver plateau
    0.46f to Color(0xFFD2D4E0),
    0.51f to Color(0xFFC5CDE5),
    0.54f to Color(0xFFC5D3ED), // bluest point (muted, as rendered)
    0.59f to Color(0xFFD4E3F0),
    0.63f to Color(0xFFDFE7EE),
    0.66f to Color(0xFFEEEEF0),
    0.71f to Color(0xFFF7F5F4), // white peak
    0.76f to Color(0xFFFAEDE2),
    0.81f to Color(0xFFF6DCC5), // peach
    0.86f to Color(0xFFDFC7B2), // tan
    0.91f to Color(0xFFBAAFAA),
    1.00f to Color(0xFFAEA6A5) // warm gray
)

// Main gradient axis: 151.367deg (screen space, y-down) and its perpendicular.
internal val HoloMainAxis = Offset(0.4787f, 0.8780f)
internal val HoloPerpAxis = Offset(-0.8780f, 0.4787f)

// Tilt drift factors of the ramp (t) and the perpendicular highlight (sShift).
internal const val HOLO_RAMP_TILT_X = 0.16f
internal const val HOLO_RAMP_TILT_Y = 0.10f
internal const val HOLO_HIGHLIGHT_TILT_X = 0.12f
internal const val HOLO_HIGHLIGHT_TILT_Y = 0.18f

// Zero-mean luminance highlight: (0.5 - sShift) * amplitude, ~ ±amplitude/2 (= ±15/255).
internal const val HOLO_HIGHLIGHT_AMPLITUDE = 0.12f

// Film grain: n = hash - bias in [-bias, 1-bias), contribution n * amp where
// amp = baseAmp * (1 - lumaFactor * luma). Cells are 0.8 density-independent points.
internal const val HOLO_GRAIN_BASE_AMP = 0.0855f
internal const val HOLO_GRAIN_LUMA_FACTOR = 0.45f
internal const val HOLO_GRAIN_BIAS = 0.4f
internal const val HOLO_GRAIN_CELL_DP = 0.8f
