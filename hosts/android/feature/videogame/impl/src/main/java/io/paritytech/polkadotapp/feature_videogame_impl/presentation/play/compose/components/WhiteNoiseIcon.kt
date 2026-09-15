package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt
import kotlin.random.Random

private const val NOISE_TEXTURE_SIZE = 160
private const val NOISE_FRAME_COUNT = 12
private const val NOISE_FRAME_DELAY_MS = 60L

// Brightest grain (0..255). Low so the static stays near-black, not white.
private const val NOISE_MAX_LUMA = 0x55

@Composable
internal fun WhiteNoiseIcon(modifier: Modifier) {
    val frames by produceState<List<ImageBitmap>?>(initialValue = null) {
        value = withContext(Dispatchers.Default) {
            List(NOISE_FRAME_COUNT) { buildNoiseFrame() }
        }
    }

    val bakedFrames = frames
    if (bakedFrames != null) {
        var frameIndex by remember { mutableIntStateOf(0) }
        LaunchedEffect(bakedFrames) {
            while (true) {
                delay(NOISE_FRAME_DELAY_MS)
                frameIndex = (frameIndex + 1) % bakedFrames.size
            }
        }

        Canvas(modifier) {
            drawImage(
                image = bakedFrames[frameIndex],
                srcOffset = IntOffset.Zero,
                srcSize = IntSize(NOISE_TEXTURE_SIZE, NOISE_TEXTURE_SIZE),
                dstOffset = IntOffset.Zero,
                dstSize = IntSize(size.width.roundToInt(), size.height.roundToInt()),
                filterQuality = FilterQuality.None
            )
        }
    }
}

private fun buildNoiseFrame(): ImageBitmap {
    val bitmap = ImageBitmap(NOISE_TEXTURE_SIZE, NOISE_TEXTURE_SIZE)
    val pixels = IntArray(NOISE_TEXTURE_SIZE * NOISE_TEXTURE_SIZE)
    for (i in pixels.indices) {
        val luma = (Random.nextFloat() * Random.nextFloat() * NOISE_MAX_LUMA).toInt()
        pixels[i] = 0xFF000000.toInt() or (luma shl 16) or (luma shl 8) or luma
    }
    bitmap.asAndroidBitmap().setPixels(pixels, 0, NOISE_TEXTURE_SIZE, 0, 0, NOISE_TEXTURE_SIZE, NOISE_TEXTURE_SIZE)
    return bitmap
}
