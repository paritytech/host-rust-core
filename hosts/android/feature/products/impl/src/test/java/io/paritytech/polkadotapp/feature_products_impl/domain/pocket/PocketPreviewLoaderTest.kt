package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import android.net.Uri
import io.paritytech.polkadotapp.feature_dotns_api.domain.DotNsResolver
import io.paritytech.polkadotapp.feature_products_api.domain.pocket.PocketCardId
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_api.model.PocketCardDefinition
import io.paritytech.polkadotapp.feature_products_impl.domain.product.ProductWorkerArchive
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.renderer.RendererNodeJsonDecoder
import io.paritytech.polkadotapp.test_shared.whenever
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.mockito.Mockito.mock
import java.io.File

private const val ONE_MEGABYTE = 1024 * 1024

class PocketPreviewLoaderTest {
    @get:Rule
    val workerArchive = TemporaryFolder()

    private val dotNsResolver: DotNsResolver = mock()
    private val loader = PocketPreviewLoader(
        archive = ProductWorkerArchive(dotNsResolver),
        faceDecoder = PocketFaceJsonDecoder(RendererNodeJsonDecoder()),
    )

    private val definition = PocketCardDefinition(id = PocketCardId("loyalty"), title = "Loyalty", preview = "face.json")

    /**
     * The preview is read on the way to the add sheet, before the user has approved anything, so how
     * much of it there is to read is entirely the product's choice. It has to be refused on its size
     * alone: this one is well-formed, and decoding it is already too late.
     */
    @Test
    fun `a preview of a megabyte is refused on its size rather than read whole`() = runBlocking {
        publishPreview(textFace("x".repeat(ONE_MEGABYTE)))

        val result = loader.load(gameProduct, definition)

        assertTrue("a megabyte of well-formed face still has to be refused", result.isFailure)
    }

    @Test
    fun `a preview of the size a real face is decodes`() = runBlocking {
        publishPreview(textFace("Loyalty"))

        val face = loader.load(gameProduct, definition).getOrThrow()

        assertEquals(JsWidget.Text(text = "Loyalty"), face)
    }

    private fun textFace(text: String) =
        """{"tag":"Text","value":{"modifiers":[],"props":{},"children":[{"tag":"String","value":{"text":"$text"}}]}}"""

    private suspend fun publishPreview(face: String) {
        File(workerArchive.root, definition.preview).writeText(face)

        val archiveUri: Uri = mock()
        whenever(archiveUri.path).thenReturn(workerArchive.root.path)
        whenever(dotNsResolver.resolveToLocalUri("worker.game.dot")).thenReturn(Result.success(archiveUri))
    }
}
