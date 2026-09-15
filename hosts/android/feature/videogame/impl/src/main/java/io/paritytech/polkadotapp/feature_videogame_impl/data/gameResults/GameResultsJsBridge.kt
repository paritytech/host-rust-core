package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import android.webkit.JavascriptInterface
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import timber.log.Timber

/**
 * `@JavascriptInterface` exposed as `window.gameResults` (name fixed by the web app). Invoked on a
 * binder thread — never touch UI from here.
 */
class GameResultsJsBridge {
    private val _events = Channel<FlowEvent>(Channel.UNLIMITED)
    val events: Flow<FlowEvent> = _events.receiveAsFlow()

    @JavascriptInterface
    fun postMessage(json: String) {
        val event = runCatching { decode(json) }.getOrElse {
            Timber.w(it, "[GameResults][bridge] decode failed json=$json")
            return
        }
        val result = _events.trySend(event)
        if (result.isFailure) {
            Timber.w("[GameResults][bridge] dropped event: $event")
        }
    }

    private fun decode(json: String): FlowEvent {
        val obj = Json.parseToJsonElement(json).jsonObject
        return when (val type = obj.string("type")) {
            "flow.ready" -> FlowEvent.Ready
            "flow.results_shown" -> FlowEvent.ResultsShown
            "flow.prize_draw_started" -> FlowEvent.PrizeDrawStarted
            "flow.prize_draw_complete" -> FlowEvent.PrizeDrawComplete(won = obj.bool("won") ?: false)
            "flow.nft_reveal_started" -> FlowEvent.NftRevealStarted(count = obj.intVal("count") ?: 0)
            "flow.nft_reveal_complete" -> FlowEvent.NftRevealComplete
            "flow.username_claim_requested" -> FlowEvent.UsernameClaimRequested
            "flow.request_display_name" -> FlowEvent.RequestDisplayName
            "flow.username_availability_needed" ->
                FlowEvent.UsernameAvailabilityNeeded(name = obj.string("name").orEmpty())
            "flow.error" ->
                FlowEvent.Error(phase = obj.string("phase").orEmpty(), detail = obj.string("detail"))
            "flow.complete" -> FlowEvent.Complete
            null -> FlowEvent.Unknown(type = "")
            else -> FlowEvent.Unknown(type)
        }
    }

    private fun JsonObject.string(key: String): String? =
        this[key]?.jsonPrimitive?.contentOrNull

    private fun JsonObject.bool(key: String): Boolean? =
        runCatching { this[key]?.jsonPrimitive?.boolean }.getOrNull()

    private fun JsonObject.intVal(key: String): Int? =
        runCatching { this[key]?.jsonPrimitive?.int }.getOrNull()
}
