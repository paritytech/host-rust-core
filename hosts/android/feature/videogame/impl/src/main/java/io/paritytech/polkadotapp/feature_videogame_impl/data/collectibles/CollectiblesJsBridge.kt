package io.paritytech.polkadotapp.feature_videogame_impl.data.collectibles

import android.webkit.JavascriptInterface
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import timber.log.Timber

class CollectiblesJsBridge {
    private val _events = Channel<CollectiblesFlowEvent>(Channel.UNLIMITED)
    val events: Flow<CollectiblesFlowEvent> = _events.receiveAsFlow()

    @JavascriptInterface
    fun postMessage(json: String) {
        val event = runCatching { decode(json) }.getOrElse {
            Timber.w(it, "[Collectibles][bridge] decode failed json=$json")
            return
        }
        val result = _events.trySend(event)
        if (result.isFailure) {
            Timber.w("[Collectibles][bridge] dropped event: $event")
        }
    }

    private fun decode(json: String): CollectiblesFlowEvent {
        val obj = Json.parseToJsonElement(json).jsonObject
        return when (val type = obj.string("type")) {
            "flow.ready" -> CollectiblesFlowEvent.Ready
            "flow.gallery_shown" -> CollectiblesFlowEvent.GalleryShown(count = obj.intVal("count") ?: 0)
            "flow.item_opened" -> CollectiblesFlowEvent.ItemOpened(hash = obj.string("hash").orEmpty())
            "flow.item_closed" -> CollectiblesFlowEvent.ItemClosed(hash = obj.string("hash").orEmpty())
            "flow.error" -> CollectiblesFlowEvent.Error(
                phase = obj.string("phase").orEmpty(),
                detail = obj.string("detail")
            )
            "flow.close" -> CollectiblesFlowEvent.Close
            null -> CollectiblesFlowEvent.Unknown(type = "")
            else -> CollectiblesFlowEvent.Unknown(type)
        }
    }

    private fun JsonObject.string(key: String): String? =
        this[key]?.jsonPrimitive?.contentOrNull

    private fun JsonObject.intVal(key: String): Int? =
        runCatching { this[key]?.jsonPrimitive?.int }.getOrNull()
}
