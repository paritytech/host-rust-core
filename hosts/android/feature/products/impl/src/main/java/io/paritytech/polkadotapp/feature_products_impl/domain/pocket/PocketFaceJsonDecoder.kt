package io.paritytech.polkadotapp.feature_products_impl.domain.pocket

import io.paritytech.polkadotapp.feature_products_api.model.JsWidget
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.renderer.RendererNodeJsonDecoder
import io.paritytech.polkadotapp.feature_products_impl.domain.truapi.renderer.toJsWidget
import javax.inject.Inject

/** A static face from an archive or the app's assets, decoded through the same mapping a live face takes. */
class PocketFaceJsonDecoder @Inject constructor(
    private val nodeDecoder: RendererNodeJsonDecoder,
) {
    fun decode(faceJson: String): Result<JsWidget> = nodeDecoder.decode(faceJson).map { it.toJsWidget() }
}
