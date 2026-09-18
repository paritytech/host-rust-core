package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_api.model.PocketCardDefinition
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_products_impl.domain.product.ProductWorkerArchive
import java.io.File
import javax.inject.Inject

/** Reads a published card's static face out of the product's worker archive. */
class PocketPreviewLoader @Inject constructor(
    private val archive: ProductWorkerArchive,
    private val faceDecoder: PocketFaceJsonDecoder,
) {
    suspend fun load(productId: ProductId, definition: PocketCardDefinition): Result<JsWidget> =
        archive.file(productId, definition.preview)
            .mapCatching { it.readFaceWithinBound() }
            .flatMap(faceDecoder::decode)

    // The preview is read before the user has approved anything, so how much there is to read is the
    // product's choice. Its size is checked rather than its content: by the time a hostile one has
    // been decoded it has already been held whole in memory.
    private fun File.readFaceWithinBound(): String {
        require(length() <= MAX_PREVIEW_BYTES) { "preview '$name' is larger than $MAX_PREVIEW_BYTES bytes" }

        return readText()
    }

    private companion object {
        const val MAX_PREVIEW_BYTES = 256L * 1024
    }
}
