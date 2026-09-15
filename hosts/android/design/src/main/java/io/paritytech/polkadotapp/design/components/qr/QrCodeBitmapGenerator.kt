package io.paritytech.polkadotapp.design.components.qr

import android.graphics.Bitmap
import android.graphics.Color
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.core.graphics.applyCanvas
import androidx.core.graphics.createBitmap
import io.github.alexzhirkevich.qrose.QrCodePainter
import io.github.alexzhirkevich.qrose.options.QrBallShape
import io.github.alexzhirkevich.qrose.options.QrFrameShape
import io.github.alexzhirkevich.qrose.options.QrOptions
import io.github.alexzhirkevich.qrose.options.QrPixelShape
import io.github.alexzhirkevich.qrose.options.circle
import io.github.alexzhirkevich.qrose.options.roundCorners
import io.github.alexzhirkevich.qrose.options.square
import io.github.alexzhirkevich.qrose.toImageBitmap
import javax.inject.Inject

class QrCodeBitmapGenerator @Inject constructor() {
    fun generate(content: String, size: Int = QR_EXPORT_SIZE): Bitmap {
        val painter = QrCodePainter(
            content,
            QrOptions {
                shapes {
                    ball = QrBallShape.square()
                    frame = QrFrameShape.roundCorners(0.3f)
                    darkPixel = QrPixelShape.circle(0.6f)
                }
            }
        )
        return createBitmap(size, size, Bitmap.Config.RGB_565).applyCanvas {
            drawColor(Color.WHITE)
            drawBitmap(painter.toImageBitmap(size, size).asAndroidBitmap(), 0f, 0f, null)
        }
    }

    private companion object {
        const val QR_EXPORT_SIZE = 512
    }
}
