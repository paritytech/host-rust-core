package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import android.graphics.BlurMaskFilter
import android.graphics.LightingColorFilter
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Shader
import android.graphics.SweepGradient
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableLongState
import androidx.compose.runtime.State
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithCache
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameUiState
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin
import android.graphics.Paint as FrameworkPaint

sealed interface PlayerFrameRole {
    val bezelColors: List<Color>
    val glowColor: Color

    data object Host : PlayerFrameRole {
        override val bezelColors = listOf(
            GameColors.hostFrameGradientStart,
            GameColors.hostFrameGradientMiddle,
            GameColors.hostFrameGradientEnd
        )
        override val glowColor = GameColors.hostFrameGlow
    }

    data object Me : PlayerFrameRole {
        override val bezelColors = listOf(
            GameColors.meFrameGradientStart,
            GameColors.meFrameGradientEnd
        )
        override val glowColor = GameColors.meFrameGlow
    }

    data object Other : PlayerFrameRole {
        override val bezelColors = listOf(
            GameColors.otherFrameGradientStart,
            GameColors.otherFrameGradientMiddle,
            GameColors.otherFrameGradientEnd
        )
        override val glowColor = GameColors.otherFrameGlow
    }
}

enum class FrameMode {
    Strong,
    Soft
}

fun PlayerUiModel.frameRole(): PlayerFrameRole = when {
    isCurrentPlayer -> PlayerFrameRole.Me
    isHost -> PlayerFrameRole.Host
    else -> PlayerFrameRole.Other
}

fun VideoGameUiState.frameMode(): FrameMode = when (this) {
    is VideoGameUiState.HostIntroduction -> FrameMode.Strong
    else -> FrameMode.Soft
}

val LocalGameFrameTimeMs = compositionLocalOf<State<Long>?> { null }

@Composable
fun ProvideGameFrameTicker(content: @Composable () -> Unit) {
    val nowMsState = remember { mutableLongStateOf(0L) }

    LaunchedEffect(Unit) { tickFrameTimeMs(nowMsState) }

    CompositionLocalProvider(
        LocalGameFrameTimeMs provides nowMsState,
        content = content
    )
}

private suspend fun tickFrameTimeMs(state: MutableLongState) {
    while (true) {
        withFrameMillis { state.longValue = it }
    }
}

private data class FrameMetrics(
    val blurDp: Float,
    val glowSpreadDp: Float,
    val driftDp: Float,
    val driftPeriodSeconds: Double,
    val breathePeriodSeconds: Double,
    val lightSweepPeriodSeconds: Double,
    val minimumGlowOpacity: Float,
    val maximumGlowOpacity: Float
)

private val StrongMetrics = FrameMetrics(
    blurDp = 28f,
    glowSpreadDp = 4f,
    driftDp = 3f,
    driftPeriodSeconds = 2.2,
    breathePeriodSeconds = 1.4,
    lightSweepPeriodSeconds = 1.4,
    minimumGlowOpacity = 0.65f,
    maximumGlowOpacity = 1.0f
)

private val SoftMetrics = FrameMetrics(
    blurDp = 10f,
    glowSpreadDp = 1f,
    driftDp = 2f,
    driftPeriodSeconds = 9.0,
    breathePeriodSeconds = 5.4,
    lightSweepPeriodSeconds = 3.0,
    minimumGlowOpacity = 0.55f,
    maximumGlowOpacity = 0.8f
)

private val FRAME_BORDER_WIDTH = 8.dp
private val FRAME_CORNER_RADIUS = 24.dp

val PlayerFrameContentShape = RoundedCornerShape(FRAME_CORNER_RADIUS - FRAME_BORDER_WIDTH / 2)
private const val BRIGHTNESS_AMPLITUDE = 0.06f
private const val BRIGHTNESS_STEPS = 16
private const val LIGHT_START_ANGLE_DEGREES = 140f
private const val LIGHT_OPACITY = 0.4f

private val brightnessFilters = Array(BRIGHTNESS_STEPS + 1) { step ->
    val amount = step.toFloat() / BRIGHTNESS_STEPS * BRIGHTNESS_AMPLITUDE
    val add = (amount * 255f).toInt().coerceIn(0, 255)
    val addArgb = (add shl 16) or (add shl 8) or add
    LightingColorFilter(0xFFFFFFFF.toInt(), addArgb)
}

@Composable
fun AnimatedPlayerFrame(
    modifier: Modifier,
    role: PlayerFrameRole,
    mode: FrameMode,
    content: @Composable () -> Unit
) {
    val metrics = when (mode) {
        FrameMode.Strong -> StrongMetrics
        FrameMode.Soft -> SoftMetrics
    }

    val frameTimeMs = rememberFrameTimeMs()
    val startTimeMsState = remember { mutableLongStateOf(0L) }

    val density = LocalDensity.current
    val borderWidthPx = with(density) { FRAME_BORDER_WIDTH.toPx() }
    val cornerRadiusPx = with(density) { FRAME_CORNER_RADIUS.toPx() }
    val blurPx = with(density) { metrics.blurDp.dp.toPx() }
    val glowSpreadPx = with(density) { metrics.glowSpreadDp.dp.toPx() }
    val driftPx = with(density) { metrics.driftDp.dp.toPx() }

    Box(modifier = modifier) {
        Box(
            modifier = Modifier
                .matchParentSize()
                .drawWithCache {
                    val w = size.width
                    val h = size.height
                    val halfBorder = borderWidthPx / 2f
                    val centerX = w / 2f
                    val centerY = h / 2f

                    val bezelColorsArgb = IntArray(role.bezelColors.size) { role.bezelColors[it].toArgb() }
                    val bezelShader = LinearGradient(
                        0f, halfBorder, 0f, h - halfBorder,
                        bezelColorsArgb, null, Shader.TileMode.CLAMP
                    )
                    val bezelPaint = FrameworkPaint().apply {
                        isAntiAlias = true
                        style = FrameworkPaint.Style.STROKE
                        strokeWidth = borderWidthPx
                        shader = bezelShader
                    }

                    val glowPaint = FrameworkPaint().apply {
                        isAntiAlias = true
                        color = role.glowColor.toArgb()
                        maskFilter = BlurMaskFilter(blurPx, BlurMaskFilter.Blur.NORMAL)
                        style = FrameworkPaint.Style.FILL
                    }

                    val lightShader = SweepGradient(
                        centerX, centerY,
                        intArrayOf(
                            Color.Transparent.toArgb(),
                            GameColors.lightSweepHighlight.copy(alpha = LIGHT_OPACITY).toArgb(),
                            Color.Transparent.toArgb()
                        ),
                        floatArrayOf(0f, 0.5f, 1f)
                    )
                    val lightMatrix = Matrix()
                    val lightPaint = FrameworkPaint().apply {
                        isAntiAlias = true
                        style = FrameworkPaint.Style.STROKE
                        strokeWidth = borderWidthPx
                        shader = lightShader
                    }

                    onDrawBehind {
                        val nowMs = frameTimeMs.value
                        if (nowMs == 0L) return@onDrawBehind
                        if (startTimeMsState.longValue == 0L) {
                            startTimeMsState.longValue = nowMs
                        }
                        val elapsedSec = (nowMs - startTimeMsState.longValue)
                            .coerceAtLeast(0L) / 1000.0

                        val driftPhase = (elapsedSec % metrics.driftPeriodSeconds) / metrics.driftPeriodSeconds
                        val breathePhase = (elapsedSec % metrics.breathePeriodSeconds) / metrics.breathePeriodSeconds
                        val lightPhase = (elapsedSec % metrics.lightSweepPeriodSeconds) / metrics.lightSweepPeriodSeconds

                        val angle = driftPhase * 2.0 * PI
                        val breatheProgress = ((1.0 - cos(breathePhase * 2.0 * PI)) / 2.0).toFloat()

                        val driftDx = cos(angle).toFloat() * driftPx
                        val driftDy = sin(angle).toFloat() * driftPx
                        val brightness = breatheProgress * BRIGHTNESS_AMPLITUDE
                        val glowOpacity = metrics.minimumGlowOpacity +
                            breatheProgress * (metrics.maximumGlowOpacity - metrics.minimumGlowOpacity)
                        val lightRotationDeg = (lightPhase * 360.0).toFloat()

                        drawIntoCanvas { canvas ->
                            val nativeCanvas = canvas.nativeCanvas

                            glowPaint.alpha = (glowOpacity * 255f).toInt().coerceIn(0, 255)
                            nativeCanvas.drawRoundRect(
                                -glowSpreadPx + driftDx,
                                -glowSpreadPx + driftDy,
                                w + glowSpreadPx + driftDx,
                                h + glowSpreadPx + driftDy,
                                cornerRadiusPx, cornerRadiusPx,
                                glowPaint
                            )

                            bezelPaint.colorFilter = if (brightness > 0f) {
                                val idx = (brightness / BRIGHTNESS_AMPLITUDE * BRIGHTNESS_STEPS)
                                    .toInt()
                                    .coerceIn(0, BRIGHTNESS_STEPS)
                                brightnessFilters[idx]
                            } else {
                                null
                            }
                            nativeCanvas.drawRoundRect(
                                halfBorder, halfBorder,
                                w - halfBorder, h - halfBorder,
                                cornerRadiusPx, cornerRadiusPx,
                                bezelPaint
                            )

                            lightMatrix.setRotate(
                                LIGHT_START_ANGLE_DEGREES + lightRotationDeg,
                                centerX, centerY
                            )
                            lightShader.setLocalMatrix(lightMatrix)
                            nativeCanvas.drawRoundRect(
                                halfBorder, halfBorder,
                                w - halfBorder, h - halfBorder,
                                cornerRadiusPx, cornerRadiusPx,
                                lightPaint
                            )
                        }
                    }
                }
        )
        Box(modifier = Modifier.padding(FRAME_BORDER_WIDTH)) {
            content()
        }
    }
}

@Composable
private fun rememberFrameTimeMs(): State<Long> {
    val provided = LocalGameFrameTimeMs.current
    return if (provided != null) {
        provided
    } else {
        val fallback = remember { mutableLongStateOf(0L) }
        LaunchedEffect(Unit) { tickFrameTimeMs(fallback) }
        fallback
    }
}
