package io.paritytech.polkadotapp.feature_wallet_impl.presentation.pocket

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.net.Uri
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.graphics.createBitmap
import androidx.core.graphics.withTranslation
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.design.components.qr.QrCodeBitmapGenerator
import io.paritytech.polkadotapp.feature_wallet_impl.domain.usecase.SaveImageUseCase
import kotlinx.coroutines.withContext
import javax.inject.Inject

class IdShareImageRenderer @Inject constructor(
    private val qrCodeBitmapGenerator: QrCodeBitmapGenerator,
    private val saveImageUseCase: SaveImageUseCase,
    private val dispatchers: CoroutineDispatchers
) {
    suspend fun render(username: String, address: String): Result<Uri> = runCatching {
        val image = withContext(dispatchers.computation) {
            val qr = qrCodeBitmapGenerator.generate(address)
            composeImage(qr, username, address)
        }
        saveImageUseCase(image)
    }

    private fun composeImage(qr: Bitmap, username: String, address: String): Bitmap {
        val qrSize = qr.width
        val width = qrSize + HORIZONTAL_PADDING * 2

        val titlePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = Color.BLACK
            textSize = TITLE_TEXT_SIZE
            typeface = Typeface.DEFAULT_BOLD
            textAlign = Paint.Align.CENTER
        }
        val addressPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ADDRESS_COLOR
            textSize = ADDRESS_TEXT_SIZE
            typeface = Typeface.MONOSPACE
        }

        val addressLayout = StaticLayout.Builder
            .obtain(address, 0, address.length, addressPaint, qrSize)
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .build()

        val titleMetrics = titlePaint.fontMetrics
        val titleHeight = titleMetrics.bottom - titleMetrics.top
        val height = (
            VERTICAL_PADDING + titleHeight + SECTION_SPACING +
                qrSize + SECTION_SPACING + addressLayout.height + VERTICAL_PADDING
            ).toInt()

        val result = createBitmap(width, height)
        val canvas = Canvas(result)
        canvas.drawColor(Color.WHITE)

        val centerX = width / 2f
        canvas.drawText(username, centerX, VERTICAL_PADDING - titleMetrics.top, titlePaint)

        val qrTop = VERTICAL_PADDING + titleHeight + SECTION_SPACING
        canvas.drawBitmap(qr, HORIZONTAL_PADDING.toFloat(), qrTop, null)

        canvas.withTranslation(HORIZONTAL_PADDING.toFloat(), qrTop + qrSize + SECTION_SPACING) {
            addressLayout.draw(this)
        }

        return result
    }

    private companion object {
        const val HORIZONTAL_PADDING = 48
        const val VERTICAL_PADDING = 48f
        const val SECTION_SPACING = 32f
        const val TITLE_TEXT_SIZE = 44f
        const val ADDRESS_TEXT_SIZE = 26f
        val ADDRESS_COLOR = Color.DKGRAY
    }
}
