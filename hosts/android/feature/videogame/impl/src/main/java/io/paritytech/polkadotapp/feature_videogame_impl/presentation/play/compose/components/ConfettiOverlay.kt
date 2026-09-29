package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import android.graphics.BlurMaskFilter
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import kotlinx.coroutines.android.awaitFrame
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import android.graphics.Paint as FrameworkPaint

@Composable
fun ConfettiOverlay(
    modifier: Modifier,
    sugarLevel: Float,
    onFinale: () -> Unit,
) {
    val density = LocalDensity.current.density
    BoxWithConstraints(modifier = modifier) {
        val widthPx = constraints.maxWidth.toFloat()
        val layout = remember(density) { makeBurstLayout(density) }
        val active = remember { mutableListOf<LiveParticle>() }
        var completion by remember { mutableIntStateOf(0) }
        var frame by remember { mutableIntStateOf(0) }
        val currentOnFinale by rememberUpdatedState(onFinale)

        LaunchedEffect(sugarLevel, widthPx) {
            if (widthPx <= 0f) return@LaunchedEffect
            val target = (sugarLevel * 100).toInt().coerceIn(0, 100)
            if (target <= completion) return@LaunchedEffect
            val willComplete = completion < 100 && target >= 100
            spawnPrefix(
                layout = layout,
                active = active,
                prevCompletion = completion,
                targetCompletion = target,
                viewWidth = widthPx,
                density = density,
                finale = if (willComplete) FINALE_GOLDEN_2 else null,
            )
            completion = target
            if (willComplete) currentOnFinale()
        }

        LaunchedEffect(Unit) {
            while (isActive) {
                awaitFrame()
                stepParticles(active)
                frame++
            }
        }

        Canvas(modifier = Modifier.fillMaxSize()) {
            frame
            active.forEach { drawParticle(it) }
        }
    }
}

@Composable
fun HaloOverlay(modifier: Modifier, playKey: Int) {
    if (playKey == 0) return
    val anim = remember(playKey) { Animatable(0f) }
    LaunchedEffect(playKey) {
        anim.snapTo(0f)
        anim.animateTo(1f, tween(HALO_DURATION_MS, easing = FastOutSlowInEasing))
    }
    val progress = anim.value
    val scale = 1f + progress * 0.7f
    val alpha = (if (progress < 0.2f) progress / 0.2f else 1f - progress) * HALO_MAX_ALPHA

    Box(modifier = modifier) {
        Canvas(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                    this.alpha = alpha
                    compositingStrategy = CompositingStrategy.Offscreen
                }
        ) {
            drawRect(
                brush = Brush.radialGradient(
                    colorStops = HALO_GRADIENT_STOPS,
                    radius = size.minDimension * (0.5f),
                    center = Offset(size.width / 2f, size.height / 2f),
                ),
                blendMode = BlendMode.Screen,
            )
        }
    }
}

private fun spawnPrefix(
    layout: List<BurstParticle>,
    active: MutableList<LiveParticle>,
    prevCompletion: Int,
    targetCompletion: Int,
    viewWidth: Float,
    density: Float,
    finale: FinaleStyle?,
) {
    val start = prevCompletion * FULL_PARTICLE_COUNT / 100
    val end = targetCompletion * FULL_PARTICLE_COUNT / 100
    val effectiveG = BASE_G * density
    for (i in start until end) {
        val p = layout[i]
        var size = p.size
        var vx = p.vx
        var vy = p.vy
        var color = p.color
        var glow = 0f
        var alphaCap = 1f
        var life = BASE_LIFE
        var rotSpeed = p.rotSpeed
        var gStart = effectiveG
        var gEnd = effectiveG
        var gPow = 1f

        if (finale != null) {
            color = finale.palette[i % finale.palette.size]
            size *= finale.sizeMul
            vx *= finale.velMul
            vy *= finale.velMul
            life = (BASE_LIFE * finale.lifeMul).toInt()
            glow = finale.glow * density
            rotSpeed *= finale.rotSpeedMul
            val baseG = effectiveG * finale.gravityMul
            gStart = baseG * finale.gravityStartMul
            gEnd = baseG * finale.gravityEndMul
            gPow = finale.gravityPower

            if (finale.heroEvery > 0) {
                if (i % finale.heroEvery == 0) {
                    size *= finale.heroSizeMul
                    glow = finale.heroGlow * density
                } else {
                    size *= finale.bokehSizeMul
                    vx *= finale.bokehVelMul
                    vy *= finale.bokehVelMul
                    alphaCap = finale.bokehAlpha
                }
            }
        }

        active.add(
            LiveParticle(
                x = viewWidth * p.xRel,
                y = -size,
                vx = vx,
                vy = vy,
                color = color,
                size = size,
                rot = p.rotation,
                rotSpeed = rotSpeed,
                glow = glow,
                alphaCap = alphaCap,
                gStart = gStart,
                gEnd = gEnd,
                gPow = gPow,
                ticksLeft = life,
                lifeStart = life,
            )
        )
    }
}

private fun stepParticles(active: MutableList<LiveParticle>) {
    active.removeAll { it.ticksLeft <= 0 }
    for (p in active) {
        val t = (p.lifeStart - p.ticksLeft).toFloat() / p.lifeStart
        val g = p.gStart + (p.gEnd - p.gStart) * t.pow(p.gPow)
        p.x += p.vx
        p.y += p.vy
        p.vx *= DECAY
        p.vy = p.vy * DECAY + g
        p.rot += p.rotSpeed
        p.ticksLeft -= 1
    }
}

private fun DrawScope.drawParticle(p: LiveParticle) {
    val fade = (p.ticksLeft / FADE_TICKS.toFloat()).coerceAtMost(1f) * p.alphaCap
    if (fade <= 0f) return
    val color = p.color.copy(alpha = fade.coerceIn(0f, 1f))
    val degrees = p.rot * (180f / PI.toFloat())
    val center = Offset(p.x, p.y)
    val isCircle = p.rotSpeed >= 0f
    val w = p.size
    val h = p.size * RECT_ASPECT

    rotate(degrees = degrees, pivot = center) {
        // Glow mirrors the particle's shape so rect particles get a rect-shaped
        // halo (matches iOS's CGContext.setShadow which softens whatever is drawn
        // next, instead of always blurring a circle behind the shape).
        if (p.glow > 0f) {
            drawIntoCanvas { canvas ->
                glowPaint.color = color.toArgb()
                glowPaint.maskFilter = blurFilter(p.glow)
                if (isCircle) {
                    canvas.nativeCanvas.drawCircle(p.x, p.y, p.size / 2f, glowPaint)
                } else {
                    canvas.nativeCanvas.drawRect(
                        p.x - w / 2f,
                        p.y - h / 2f,
                        p.x + w / 2f,
                        p.y + h / 2f,
                        glowPaint,
                    )
                }
            }
        }

        if (isCircle) {
            drawCircle(color = color, radius = p.size / 2f, center = center)
        } else {
            drawRect(
                color = color,
                topLeft = Offset(p.x - w / 2f, p.y - h / 2f),
                size = Size(w, h),
            )
        }
    }
}

private val glowPaint = FrameworkPaint().apply {
    isAntiAlias = true
    style = FrameworkPaint.Style.FILL
}

private val blurFilters = mutableMapOf<Float, BlurMaskFilter>()
private fun blurFilter(radius: Float): BlurMaskFilter =
    blurFilters.getOrPut(radius) { BlurMaskFilter(radius, BlurMaskFilter.Blur.NORMAL) }

private fun makeBurstLayout(density: Float): List<BurstParticle> {
    val r = SeededRng()
    return List(FULL_PARTICLE_COUNT) {
        val angle = r.next() * PI
        val speed = 12.0 * (0.85 + r.next() * 0.30) * density
        BurstParticle(
            vx = (cos(angle) * speed).toFloat(),
            vy = (sin(angle) * speed).toFloat(),
            color = CONFETTI_COLORS[(r.next() * CONFETTI_COLORS.size).toInt()],
            size = ((5 + r.next() * 4) * 1.2 * density).toFloat(),
            xRel = (0.15 + r.next() * 0.70).toFloat(),
            rotation = (r.next() * PI * 2).toFloat(),
            rotSpeed = ((r.next() - 0.5) * 0.3).toFloat(),
        )
    }
}

private data class BurstParticle(
    val vx: Float,
    val vy: Float,
    val color: Color,
    val size: Float,
    val xRel: Float,
    val rotation: Float,
    val rotSpeed: Float,
)

private data class LiveParticle(
    var x: Float,
    var y: Float,
    var vx: Float,
    var vy: Float,
    val color: Color,
    val size: Float,
    var rot: Float,
    val rotSpeed: Float,
    val glow: Float,
    val alphaCap: Float,
    val gStart: Float,
    val gEnd: Float,
    val gPow: Float,
    var ticksLeft: Int,
    val lifeStart: Int,
)

private data class FinaleStyle(
    val palette: List<Color>,
    val sizeMul: Float,
    val velMul: Float,
    val lifeMul: Float,
    val glow: Float,
    val gravityMul: Float,
    val rotSpeedMul: Float,
    val gravityStartMul: Float = 1f,
    val gravityEndMul: Float = 1f,
    val gravityPower: Float = 1f,
    val heroEvery: Int = 0,
    val heroSizeMul: Float = 1f,
    val heroGlow: Float = 0f,
    val bokehSizeMul: Float = 1f,
    val bokehAlpha: Float = 1f,
    val bokehVelMul: Float = 1f,
)

private class SeededRng(seed: Int = 42) {
    private var state = seed
    fun next(): Double {
        state += 0x6D2B79F5.toInt()
        var t = state
        t = (t xor (t ushr 15)) * (t or 1)
        t = t xor (t + ((t xor (t ushr 7)) * (t or 61)))
        return ((t xor (t ushr 14)).toLong() and 0xFFFFFFFFL).toDouble() / 4294967296.0
    }
}

private val GOLD_PALETTE = listOf(
    Color(0xFFFFD700),
)

private val FINALE_GOLDEN_2 = FinaleStyle(
    palette = GOLD_PALETTE,
    sizeMul = 1.3f,
    velMul = 1.05f,
    lifeMul = 1.15f,
    glow = 8f,
    gravityMul = 1.05f,
    rotSpeedMul = 0.4f,
    gravityStartMul = 0.45f,
    gravityEndMul = 4.0f,
    gravityPower = 2.0f,
    heroEvery = 3,
    heroSizeMul = 0.98f,
    heroGlow = 12f,
    bokehSizeMul = 0.45f,
    bokehAlpha = 0.55f,
    bokehVelMul = 0.7f,
)

private val CONFETTI_COLORS = listOf(
    Color(0xFF6BE170),
    Color(0xFF413B9C),
    Color(0xFF3B60F5),
    Color(0xFF503DA7),
)

private val HALO_GRADIENT_STOPS = arrayOf(
    0.00f to Color(0xFAFFF5C8),
    0.18f to Color(0xEBFFD700),
    0.36f to Color(0xC7FFD700),
    0.54f to Color(0x8CDCB400),
    0.72f to Color(0x40AA8700),
    0.88f to Color.Transparent,
)

private const val FULL_PARTICLE_COUNT = 180
private const val BASE_LIFE = 120
private const val BASE_G = 0.20f
private const val DECAY = 0.9f
private const val FADE_TICKS = 30
private const val HALO_DURATION_MS = 2000
private const val HALO_MAX_ALPHA = 0.5f
private const val RECT_ASPECT = 0.4f
