package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.withInfiniteAnimationFrameNanos
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.design.components.icon.NovaIcon
import io.paritytech.polkadotapp.design.components.icon.NovaIcons
import io.paritytech.polkadotapp.design.components.icon.vectors.Play
import io.paritytech.polkadotapp.design.components.icon.vectors.VideoPause
import io.paritytech.polkadotapp.design.components.surface.PolkadotSurface
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.icons.Music
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.sin

@Composable
fun MusicIndicator(
    playing: Boolean,
    onToggle: () -> Unit,
) {
    PolkadotSurface(
        shape = PolkadotTheme.shapes.full,
        color = Color(0xA8000000),
        border = BorderStroke(PolkadotTheme.borders.default, Color.White.copy(alpha = 0.08f)),
        onClick = onToggle
    ) {
        Row(
            modifier = Modifier.padding(
                horizontal = PolkadotTheme.spacings.extraMedium,
                vertical = PolkadotTheme.spacings.small,
            ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(PolkadotTheme.spacings.small),
        ) {
            PlayPauseIcon(playing = playing)
            MusicWave(playing = playing)
            QuaverNote(playing = playing)
        }
    }
}

@Composable
private fun PlayPauseIcon(playing: Boolean) {
    NovaIcon(
        modifier = Modifier.size(14.dp),
        imageVector = if (playing) NovaIcons.VideoPause else NovaIcons.Play,
        tint = Color.White
    )
}

// Renders two layered sine waves that animate horizontally. The amplitude fades in/out
// with the playing state, and phase advances continuously to create a flowing motion effect.
@Composable
private fun MusicWave(
    playing: Boolean,
) {
    val amplitude by animateFloatAsState(
        targetValue = if (playing) 1f else 0f,
        animationSpec = tween(800),
        label = "waveAmplitude"
    )

    var phase by remember { mutableFloatStateOf(0f) }
    val currentPlaying by rememberUpdatedState(playing)

    LaunchedEffect(Unit) {
        var lastNanos = 0L
        while (isActive) {
            withInfiniteAnimationFrameNanos { nanos ->
                if (lastNanos != 0L) {
                    val dt = (nanos - lastNanos) / 1_000_000_000f
                    val speed = if (currentPlaying) 1.08f else 0.24f
                    phase += speed * dt
                }
                lastNanos = nanos
            }
        }
    }

    val paths = remember { Array(2) { Path() } }

    Canvas(modifier = Modifier.size(width = 36.dp, height = 14.dp)) {
        drawWaveLayers(amplitude, phase, paths)
    }
}

// Draws two overlapping sine-wave strokes with different frequencies, phase offsets, and opacities.
// Each wave is shaped by a sin-envelope that tapers to zero at the edges, producing a lens-shaped
// oscillation. The `amplitude` parameter (0..1) controls wave height and opacity for fade transitions.
private fun DrawScope.drawWaveLayers(amplitude: Float, phase: Float, paths: Array<Path>) {
    val w = size.width
    val h = size.height

    for (layer in 0..1) {
        val layerAmp = amplitude * if (layer == 0) 1f else 0.6f
        val freq = if (layer == 0) 1.8f else 2.6f
        val phaseOffset = if (layer == 0) 0f else 1.2f
        val opacity = if (layer == 0) 0.9f else 0.35f
        val strokeWidth = if (layer == 0) 1.8f else 1.3f

        val path = paths[layer].apply { reset() }
        val steps = 40

        for (x in 0..steps) {
            val t = x / steps.toFloat()
            val xPos = t * w
            val envelope = sin(t * PI).toFloat()
            val y = h / 2 + sin(
                t * PI.toFloat() * freq + phase * (3 + layer) + phaseOffset
            ).toFloat() * (h * 0.35f) * layerAmp * envelope

            if (x == 0) path.moveTo(xPos, y) else path.lineTo(xPos, y)
        }

        drawPath(
            path = path,
            color = Color.White.copy(alpha = opacity * (0.3f + amplitude * 0.7f)),
            style = Stroke(
                width = strokeWidth.dp.toPx(),
                cap = StrokeCap.Round,
                join = StrokeJoin.Round
            )
        )
    }
}

@Composable
private fun QuaverNote(playing: Boolean) {
    val noteAlpha by animateFloatAsState(
        targetValue = if (playing) 0.8f else 0.3f,
        animationSpec = tween(500),
        label = "noteAlpha"
    )

    val infiniteTransition = rememberInfiniteTransition(label = "noteTransition")
    val floatOffset by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = -2.5f,
        animationSpec = infiniteRepeatable(
            animation = tween(1250, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "noteFloat"
    )

    NovaIcon(
        modifier = Modifier
            .size(16.dp)
            .graphicsLayer {
                alpha = noteAlpha
                translationY = if (playing) floatOffset else 0f
            },
        imageVector = Music,
        tint = Color.White
    )
}

@Preview
@Composable
private fun MusicIndicatorPlayingPreview() {
    PolkadotTheme {
        MusicIndicator(playing = true, onToggle = {})
    }
}

@Preview
@Composable
private fun MusicIndicatorPausedPreview() {
    PolkadotTheme {
        MusicIndicator(playing = false, onToggle = {})
    }
}
