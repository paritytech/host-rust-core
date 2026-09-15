package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.Attestations
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.GameResultsInput
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.MemberState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.PrizeDraw
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.UsernameAvailability
import io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults.UsernameClaim
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class GameResultsPayloadJsonTest {
    private fun encode(input: GameResultsInput): JsonObject =
        Json.parseToJsonElement(GameResultsPayloadJson.encode(input)).jsonObject

    @Test
    fun `encodes the new prize-draw shape and omits legacy fields`() {
        val input = baseInput(
            prizeDraw = PrizeDraw(
                prizeUsd = 200.toBigDecimal(),
                userTicket = "a".repeat(64),
                winningTickets = listOf("b".repeat(64), "c".repeat(64)),
                ticketDistance = 0L,
                totalEntries = 12_000L,
                nextDrawAt = "2026-06-02T00:00:00Z",
                won = true
            )
        )

        val draw = encode(input)["prizeDraw"]!!.jsonObject

        assertEquals(200.0, draw["prizeUsd"]!!.jsonPrimitive.content.toDouble())
        assertEquals("a".repeat(64), draw["userTicket"]!!.jsonPrimitive.content)
        assertEquals(2, draw["winningTickets"]!!.jsonArray.size)
        assertEquals(0L, draw["ticketDistance"]!!.jsonPrimitive.content.toLong())
        assertEquals(12_000L, draw["totalEntries"]!!.jsonPrimitive.content.toLong())
        assertEquals("2026-06-02T00:00:00Z", draw["nextDrawAt"]!!.jsonPrimitive.content)
        assertTrue(draw["won"]!!.jsonPrimitive.content.toBoolean())
        // Legacy fields are gone.
        assertFalse(draw.containsKey("kind"))
        assertFalse(draw.containsKey("seed"))
    }

    @Test
    fun `null prizeDraw is emitted as JSON null`() {
        val json = encode(baseInput(prizeDraw = null))
        assertEquals(JsonNull, json["prizeDraw"])
    }

    @Test
    fun `member omits all rank fields`() {
        val input = baseInput(
            member = MemberState(justBecameMember = false, displayName = null, memberSince = null)
        )

        val member = encode(input)["member"]!!.jsonObject

        assertFalse(member.containsKey("demoted"))
        assertFalse(member.containsKey("rankBefore"))
        assertFalse(member.containsKey("rankAfter"))
        assertFalse(member.containsKey("gamesInRank"))
        assertFalse(member.containsKey("gamesPerRank"))
        assertFalse(member["justBecameMember"]!!.jsonPrimitive.content.toBoolean())
    }

    @Test
    fun `username availability is emitted as its wire value`() {
        val input = baseInput(
            usernameClaim = UsernameClaim(
                eligible = true,
                suggestedUsername = "byteboro",
                previousUsername = null,
                availability = UsernameAvailability.TAKEN,
                alternatives = listOf("byteboro1", "byteboro2")
            )
        )

        val claim = encode(input)["usernameClaim"]!!.jsonObject

        assertEquals("taken", claim["availability"]!!.jsonPrimitive.content)
        assertEquals(2, claim["alternatives"]!!.jsonArray.size)
    }

    @Test
    fun `empty alternatives are omitted`() {
        val input = baseInput(
            usernameClaim = UsernameClaim(
                eligible = true,
                suggestedUsername = null,
                previousUsername = null,
                availability = UsernameAvailability.AVAILABLE,
                alternatives = emptyList()
            )
        )

        val claim = encode(input)["usernameClaim"]!!.jsonObject

        assertEquals("available", claim["availability"]!!.jsonPrimitive.contentOrNull)
        assertFalse(claim.containsKey("alternatives"))
    }

    private fun baseInput(
        member: MemberState = MemberState(justBecameMember = true, displayName = null, memberSince = null),
        prizeDraw: PrizeDraw? = null,
        usernameClaim: UsernameClaim = UsernameClaim(
            eligible = false,
            suggestedUsername = null,
            previousUsername = null,
            availability = null,
            alternatives = null
        )
    ) = GameResultsInput(
        attestations = Attestations(score = 8, total = 10, passed = true),
        member = member,
        prizeDraw = prizeDraw,
        usernameClaim = usernameClaim,
        attestationHashes = emptyList(),
        claim = null
    )
}
