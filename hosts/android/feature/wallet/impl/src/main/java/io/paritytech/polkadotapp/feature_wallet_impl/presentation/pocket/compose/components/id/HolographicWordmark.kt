package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.components.id

import android.content.res.Resources
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.PorterDuffXfermode
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.imageResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.core.graphics.createBitmap
import io.paritytech.polkadotapp.feature_wallet_impl.R
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation.TiltState
import io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket.compose.animation.holographicSurface
import kotlin.math.roundToInt

// Inner shadow of the wordmark letterforms (iOS HolographicWordmarkView parity): tint + offset +
// blur are kept proportional to the wordmark bitmap so the look survives density buckets. The iOS
// reference is offset y=1.5pt / radius 1pt on a 90.5553pt-tall wordmark.
private const val INNER_SHADOW_COLOR = 0xFF90AAD8

private const val WM_REFERENCE_HEIGHT = 90.5553f
private const val INNER_SHADOW_OFFSET_RATIO = 1.5f / WM_REFERENCE_HEIGHT
private const val INNER_SHADOW_RADIUS_RATIO = 1f / WM_REFERENCE_HEIGHT

private const val WM_WIDTH_RATIO = 420f / 372f
private const val WM_HEIGHT_RATIO = 0.214f
private const val WM_REST_Y_RATIO = 0.659f

// The wordmark letterforms cut out of a holographic fill (DstIn), finished with an inner shadow
// (Multiply), all composited in one offscreen layer.
@Composable
internal fun HolographicWordmark(
    cardWidth: Dp,
    cardHeight: Dp,
    tiltState: State<TiltState>
) {
    val resources = LocalContext.current.resources
    val wordmark = remember { cachedWordmark(resources) }
    val innerShadow = remember(wordmark) { cachedInnerShadow(wordmark) }

    val wmWidth = cardWidth * WM_WIDTH_RATIO
    val wmHeight = wmWidth * WM_HEIGHT_RATIO

    Box(
        modifier = Modifier
            .requiredSize(wmWidth, wmHeight)
            .graphicsLayer {
                translationY = cardHeight.toPx() * WM_REST_Y_RATIO
                compositingStrategy = CompositingStrategy.Offscreen
            }
            .holographicSurface(tiltState, lagged = true)
            .drawWithContent {
                drawContent()
                val dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt())
                drawImage(wordmark, dstSize = dstSize, blendMode = BlendMode.DstIn)
                drawImage(innerShadow, dstSize = dstSize, blendMode = BlendMode.Multiply)
            }
    )
}

// The wordmark decode and the software blur below are expensive (the blur takes ~hundreds of ms
// on low-end devices) and the wordmark is a single static resource, so both results are cached
// process-wide instead of per composition — the card is composed repeatedly (list + details +
// every shared-element transition).
private var wordmarkCache: ImageBitmap? = null
private var innerShadowCache: ImageBitmap? = null

private fun cachedWordmark(resources: Resources): ImageBitmap =
    wordmarkCache ?: ImageBitmap.imageResource(resources, R.drawable.member_card_polkadot_wordmark)
        .also { wordmarkCache = it }

private fun cachedInnerShadow(wordmark: ImageBitmap): ImageBitmap =
    innerShadowCache ?: buildInnerShadow(wordmark).also { innerShadowCache = it }

// Bakes the inner-shadow layer once from the wordmark alpha: tinted letterforms with the
// offset-and-blurred letterforms erased (DstOut), leaving shadow only along the top inner edge.
private fun buildInnerShadow(wordmark: ImageBitmap): ImageBitmap {
    val source = wordmark.asAndroidBitmap()
    val shadow = createBitmap(source.width, source.height)
    val canvas = Canvas(shadow)

    val tintPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        colorFilter = PorterDuffColorFilter(INNER_SHADOW_COLOR.toInt(), PorterDuff.Mode.SRC_IN)
    }
    canvas.drawBitmap(source, 0f, 0f, tintPaint)

    val erasePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
        maskFilter = BlurMaskFilter(source.height * INNER_SHADOW_RADIUS_RATIO, BlurMaskFilter.Blur.NORMAL)
    }
    canvas.drawBitmap(source, 0f, source.height * INNER_SHADOW_OFFSET_RATIO, erasePaint)

    return shadow.asImageBitmap()
}
