package io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles

import android.webkit.WebView
import io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles.CollectionInput
import io.paritytech.polkadotapp.feature_videogame_impl.domain.collectibles.OwnedNft
import kotlinx.serialization.json.Json

class CollectiblesJsSender(
    private val webView: WebView,
    private val json: Json
) {
    fun deliverCollection(input: CollectionInput) {
        val payload = CollectiblesPayloadJson.encodeCollection(json, input)
        val script = "window.setCollection && window.setCollection($payload);"
        webView.evaluateJavascript(script, null)
    }

    fun pushNft(item: OwnedNft) {
        val payload = CollectiblesPayloadJson.encodeNft(json, item)
        val script = "window.pushNft && window.pushNft($payload);"
        webView.evaluateJavascript(script, null)
    }
}
