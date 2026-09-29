package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import android.webkit.WebView
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.AttestationPush
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsInput
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.UsernameAvailability
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive

/**
 * Native → WebView outbound channel. Each method invokes a global the web app registers at module
 * load; calls before React mounts are buffered web-side. Main thread only.
 */
class GameResultsJsSender(private val webView: WebView) {
    fun deliverInput(input: GameResultsInput) {
        call("setGameResults", GameResultsPayloadJson.encode(input))
    }

    /**
     * Delivers the pass-gated outcome (NATIVE_SPEC §2.5). Fired once the result is known —
     * upfront for an already-passed payload, or at the mid-stream pass upgrade; the webview
     * shows the verdict/draw off this call regardless of what the first payload carried.
     */
    fun deliverOutcome(input: GameResultsInput) {
        call("setGameOutcome", GameResultsPayloadJson.encodeOutcome(input))
    }

    /** Answers `flow.request_display_name`. JS drops empty strings, so no filtering here. */
    fun deliverDisplayName(name: String) {
        call("setDisplayName", Json.encodeToString(JsonPrimitive.serializer(), JsonPrimitive(name)))
    }

    /** Answers `flow.username_availability_needed` (or pushed proactively). */
    fun deliverUsernameAvailability(
        availability: UsernameAvailability,
        alternatives: List<String>?
    ) {
        val payload = UsernameAvailabilityPayload(
            availability = availability.wireValue,
            alternatives = alternatives?.takeIf { it.isNotEmpty() },
        )
        call("setUsernameAvailability", json.encodeToString(UsernameAvailabilityPayload.serializer(), payload))
    }

    /** Streams one passed-attestation for the NFT-reveal shelf. */
    fun pushAttestation(push: AttestationPush) {
        val payload = AttestationPushPayload(
            index = push.index,
            hash = push.hash,
            // Advisory hint: emit only when true, so the absent/false cases stay off the wire.
            highValue = push.highValue?.takeIf { it },
        )
        call("pushAttestation", json.encodeToString(AttestationPushPayload.serializer(), payload))
    }

    // Guarded so calls arriving before the web app registers the global are no-ops, not JS errors.
    private fun call(global: String, argsJson: String) {
        webView.evaluateJavascript("if (window.$global) { window.$global($argsJson); }", null)
    }

    // explicitNulls = false so absent optional fields (alternatives, highValue) are omitted rather
    // than emitted as null — the web side treats absent and null identically.
    @Serializable
    private data class UsernameAvailabilityPayload(
        val availability: String,
        val alternatives: List<String>?,
    )

    @Serializable
    private data class AttestationPushPayload(
        val index: Int,
        val hash: String,
        val highValue: Boolean?,
    )

    private companion object {
        val json = Json { explicitNulls = false }
    }
}
