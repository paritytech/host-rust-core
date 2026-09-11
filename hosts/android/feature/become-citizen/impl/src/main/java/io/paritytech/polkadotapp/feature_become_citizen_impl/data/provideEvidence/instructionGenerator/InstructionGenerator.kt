package io.paritytech.polkadotapp.feature_become_citizen_impl.data.provideEvidence.instructionGenerator

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.pdf.PdfDocument
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.content.res.ResourcesCompat
import coil.ImageLoader
import coil.request.ImageRequest
import coil.request.SuccessResult
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.utils.getDrawableCompat
import io.paritytech.polkadotapp.feature_become_citizen_api.domain.models.TattooId
import io.paritytech.polkadotapp.feature_become_citizen_api.presentation.common.TattooImageLoader
import io.paritytech.polkadotapp.feature_become_citizen_impl.R
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon
import io.paritytech.polkadotapp.designsystem.R as RDesign

class InstructionGenerator @Inject constructor(
    @param:ApplicationContext private val context: Context,
    private val tattooImageLoader: TattooImageLoader,
    private val imageLoader: ImageLoader
) {
    private val pagesCount = 3

    private val a4PageHeight = 842 // 29.7cm
    private val a4PageWidth = 595 // 21cm

    private val verticalPagePadding = 40f
    private val horizontalPagePadding = 64f

    private val tattooBigSize = 142 // 5cm
    private val tattooMidSize = 106 // 3.7cm
    private val tattooSmallSize = 71 // 2.5cm

    private val tattoosMargin = 32

    private val font = ResourcesCompat.getFont(context, RDesign.font.inter_variable)

    private val titleTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        textSize = 14f
        typeface = font
        fontVariationSettings = "'wght' 600"
    }

    private val subtitleTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        textSize = 12f
        typeface = font
        fontVariationSettings = "'wght' 500"
    }

    private val regularTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        textSize = 14f
        typeface = font
        fontVariationSettings = "'wght' 400"
    }

    private val footerTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.BLACK
        alpha = 115
        textSize = 12f
        typeface = font
        fontVariationSettings = "'wght' 500"
    }

    suspend fun generatePdfInto(
        pdfDocument: PdfDocument,
        tattooId: TattooId,
        familyId: ByteArray
    ) {
        repeat(pagesCount) { index ->
            val pageInfo = PdfDocument.PageInfo.Builder(a4PageWidth, a4PageHeight, index).create()
            val page = pdfDocument.startPage(pageInfo)

            when (index) {
                0 -> page.canvas.drawFirstPage(tattooId, familyId)
                1 -> page.canvas.drawSecondPage()
                2 -> page.canvas.drawThirdPage()
            }

            pdfDocument.finishPage(page)
        }
    }

    private suspend fun Canvas.drawFirstPage(tattooId: TattooId, familyId: ByteArray) {
        drawText(context.getString(RCommon.string.tattoo_instructions_stencil_title), horizontalPagePadding, verticalPagePadding, titleTextPaint)

        val imageRequest = ImageRequest.Builder(context)
            .data(tattooImageLoader.getTattooImage(tattooId, familyId).loadable)
            .allowHardware(false)
            .build()

        when (val result = imageLoader.execute(imageRequest)) {
            is SuccessResult -> result.drawable
            else -> null
        }?.let {
            val tattoosContainerHeight = tattooBigSize + tattooMidSize + tattooSmallSize + (tattoosMargin * 2)
            val bigTattooY = a4PageHeight / 2f - tattoosContainerHeight / 2
            val midTattooY = bigTattooY + tattooBigSize + tattoosMargin
            val smallTattooY = midTattooY + tattooMidSize + tattoosMargin

            save()
            translate(a4PageWidth / 2f - tattooBigSize / 2, bigTattooY)
            it.setBounds(0, 0, tattooBigSize, tattooBigSize)
            it.draw(this)
            restore()

            save()
            translate(a4PageWidth / 2f - tattooMidSize / 2f, midTattooY)
            it.setBounds(0, 0, tattooMidSize, tattooMidSize)
            it.draw(this)
            restore()

            save()
            translate(a4PageWidth / 2f - tattooSmallSize / 2f, smallTattooY)
            it.setBounds(0, 0, tattooSmallSize, tattooSmallSize)
            it.draw(this)
            restore()

            drawFooter(1)
        }
    }

    private fun Canvas.drawSecondPage() {
        drawText(context.getString(RCommon.string.tattoo_instructions_location_title), horizontalPagePadding, verticalPagePadding, titleTextPaint)

        val locationText = context.getString(RCommon.string.tattoo_instructions_location_description)
        val locationLayout = StaticLayout.Builder.obtain(
            locationText,
            0,
            locationText.length,
            regularTextPaint,
            360
        ).build()

        save()
        translate(
            horizontalPagePadding,
            68f
        )
        locationLayout.draw(this)
        restore()

        drawText(context.getString(RCommon.string.tattoo_instructions_location_subtitle), horizontalPagePadding, 207f, subtitleTextPaint)
        val armImage = context.getDrawableCompat(R.drawable.img_arm)
        armImage.setBounds(0, 0, 402, 443)
        save()
        translate(
            a4PageWidth / 2f - 402 / 2f,
            226f
        )
        armImage.draw(this)
        restore()

        drawFooter(2)
    }

    private fun Canvas.drawThirdPage() {
        drawText(context.getString(RCommon.string.tattoo_instructions_proof_of_ink_title), horizontalPagePadding, verticalPagePadding, titleTextPaint)

        val proofOfEvidenceText = context.getString(RCommon.string.tattoo_instructions_proof_of_ink_description)
        val proofOfEvidenceLayout = StaticLayout.Builder.obtain(
            proofOfEvidenceText,
            0,
            proofOfEvidenceText.length,
            regularTextPaint,
            444
        ).build()

        save()
        translate(
            horizontalPagePadding,
            68f
        )
        proofOfEvidenceLayout.draw(this)
        restore()

        val documentationImage = context.getDrawableCompat(R.drawable.img_proof_of_ink_documentation)
        documentationImage.setBounds(0, 0, 182, 245)
        save()
        translate(
            horizontalPagePadding,
            192f
        )
        documentationImage.draw(this)
        restore()

        drawText(context.getString(RCommon.string.tattoo_instructions_documentation_title), 302f, 271f, titleTextPaint)
        val documentationVideoText = context.getString(RCommon.string.tattoo_instructions_documentation_description)
        val documentationVideoLayout = StaticLayout.Builder.obtain(
            documentationVideoText,
            0,
            documentationVideoText.length,
            regularTextPaint,
            229
        ).build()

        save()
        translate(
            302f,
            297f
        )
        documentationVideoLayout.draw(this)
        restore()

        val finalPhotoImage = context.getDrawableCompat(R.drawable.img_proof_of_ink_final_photo)
        finalPhotoImage.setBounds(0, 0, 182, 243)
        save()
        translate(
            302f,
            477f
        )
        finalPhotoImage.draw(this)
        restore()

        drawText(context.getString(RCommon.string.tattoo_instructions_final_photo_title), horizontalPagePadding, 569f, titleTextPaint)
        val finalPhotoText = context.getString(RCommon.string.tattoo_instructions_final_photo_description)
        val finalPhotoLayout = StaticLayout.Builder.obtain(
            finalPhotoText,
            0,
            finalPhotoText.length,
            regularTextPaint,
            206
        ).build()

        save()
        translate(
            horizontalPagePadding,
            595f
        )
        finalPhotoLayout.draw(this)
        restore()

        drawFooter(3)
    }

    private fun Canvas.drawFooter(pageNumber: Int) {
        drawText(
            context.getString(RCommon.string.tattoo_instructions_page_footer),
            horizontalPagePadding,
            a4PageHeight - verticalPagePadding - footerTextPaint.textSize,
            footerTextPaint
        )
        val pageCounterText = context.getString(RCommon.string.tattoo_instructions_page_footer_counter, pageNumber, 3)
        drawText(
            pageCounterText,
            a4PageWidth - horizontalPagePadding - footerTextPaint.measureText(pageCounterText),
            a4PageHeight - verticalPagePadding - footerTextPaint.textSize,
            footerTextPaint
        )
    }
}
