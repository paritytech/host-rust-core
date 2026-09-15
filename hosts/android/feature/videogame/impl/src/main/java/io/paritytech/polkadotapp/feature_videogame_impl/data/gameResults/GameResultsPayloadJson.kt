package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsInput
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.MemberState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.PrizeDraw
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.UsernameClaim
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.encodeToJsonElement

/** Encodes [GameResultsInput] for `window.setGameResults(...)`. */
internal object GameResultsPayloadJson {
    // explicitNulls = false so optional fields (displayName, suggestedUsername,
    // availability, …) are omitted rather than emitted as null — the web side
    // treats absent and null identically, and omitting keeps the payload lean.
    private val json = Json { explicitNulls = false }

    fun encode(input: GameResultsInput): String =
        json.encodeToString(GameResultsInputJson.serializer(), input.toJson(json))

    /**
     * Encodes the pass-gated outcome for `window.setGameOutcome(...)` (NATIVE_SPEC §2.5). The
     * webview synthesizes its outcome ONCE from the first `setGameResults`, so a result that
     * resolves to passed after the fast-open re-delivery never reaches the verdict/draw screens
     * without this call.
     */
    fun encodeOutcome(input: GameResultsInput): String =
        json.encodeToString(GameOutcomeJson.serializer(), input.toOutcomeJson(json))
}

@Serializable
private data class GameResultsInputJson(
    val attestations: AttestationsJson,
    val member: MemberJson,
    // JsonElement (non-nullable) so null is emitted as JsonNull rather than a missing key.
    val prizeDraw: JsonElement,
    val usernameClaim: UsernameClaimJson,
)

@Serializable
private data class AttestationsJson(val score: Int, val total: Int, val passed: Boolean)

@Serializable
private data class GameOutcomeJson(
    val passed: Boolean,
    val justBecameMember: Boolean,
    // JsonElement (non-nullable) so null is emitted as JsonNull rather than a missing key.
    val prizeDraw: JsonElement,
    val usernameClaim: UsernameClaimJson,
)

@Serializable
private data class MemberJson(
    val justBecameMember: Boolean,
    val displayName: String?,
    val memberSince: String?,
)

@Serializable
private data class PrizeDrawJson(
    val prizeUsd: Double,
    val userTicket: String,
    val winningTickets: List<String>,
    val ticketDistance: Long,
    val totalEntries: Long,
    val nextDrawAt: String,
    val won: Boolean,
)

@Serializable
private data class UsernameClaimJson(
    val eligible: Boolean,
    val suggestedUsername: String?,
    val previousUsername: String?,
    val availability: String?,
    val alternatives: List<String>?,
)

private fun GameResultsInput.toJson(json: Json) = GameResultsInputJson(
    attestations = AttestationsJson(attestations.score, attestations.total, attestations.passed),
    member = member.toJson(),
    prizeDraw = prizeDraw?.let { json.encodeToJsonElement(it.toJson()) } ?: JsonNull,
    usernameClaim = usernameClaim.toJson(),
)

private fun GameResultsInput.toOutcomeJson(json: Json) = GameOutcomeJson(
    passed = attestations.passed,
    justBecameMember = member.justBecameMember,
    prizeDraw = prizeDraw?.let { json.encodeToJsonElement(it.toJson()) } ?: JsonNull,
    usernameClaim = usernameClaim.toJson(),
)

private fun MemberState.toJson() = MemberJson(
    justBecameMember = justBecameMember,
    displayName = displayName,
    memberSince = memberSince,
)

private fun PrizeDraw.toJson() = PrizeDrawJson(
    prizeUsd = prizeUsd.toDouble(),
    userTicket = userTicket,
    winningTickets = winningTickets,
    ticketDistance = ticketDistance,
    totalEntries = totalEntries,
    nextDrawAt = nextDrawAt,
    won = won,
)

private fun UsernameClaim.toJson() = UsernameClaimJson(
    eligible = eligible,
    suggestedUsername = suggestedUsername,
    previousUsername = previousUsername,
    availability = availability?.wireValue,
    alternatives = alternatives?.takeIf { it.isNotEmpty() },
)
