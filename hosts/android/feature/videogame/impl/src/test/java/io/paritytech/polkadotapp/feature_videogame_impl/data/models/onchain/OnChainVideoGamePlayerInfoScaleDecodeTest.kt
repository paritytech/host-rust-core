package io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decode
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.DictEnum
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.Struct
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNull
import junit.framework.TestCase.assertTrue
import org.junit.Test
import java.math.BigInteger

/**
 * Regression guard for the runtime `Player` SCALE drift that crash-looped decode in prod.
 *
 * WHAT THIS GUARDS — and WHY it is the production path:
 * The app decodes on-chain `Player` storage via the substrate-sdk *by-NAME metadata* path
 * (`koltinx_serialization_scale.Scale` -> `PrimitiveDecoder`/`StructDecoder.decodeIdentity`),
 * which matches each `@Serializable` field of [OnChainVideoGamePlayerInfo] against a typed
 * value by its FIELD NAME (a `Struct.Instance` map for structs, a `DictEnum.Entry` for enum
 * variants). These tests reconstruct exactly that input shape and decode through the real
 * `Scale` format, so they exercise the same codec production uses — not a positional byte
 * round-trip (a `BinaryScale` round-trip would use a DIFFERENT codec and give false confidence;
 * see the spec note in the task).
 *
 * The v0.9.0 individuality change replaced `externally_recognized` + `zero_score` with
 * `disposition: PlayerDisposition{Keep,ArchiveKickable,ArchiveUnkickable}`. Because the metadata
 * path matches by name, a model that still expected `externallyRecognized` would not find its
 * field in the runtime `Struct.Instance` and would fail to decode — which is precisely what the
 * `rejects the OLD externallyRecognized shape` test below pins. If someone re-adds/renames a
 * field on the Kotlin model so it no longer matches the runtime struct, these tests fail.
 */
class OnChainVideoGamePlayerInfoScaleDecodeTest {
    private fun dispositionEntry(variant: String): DictEnum.Entry<Any?> =
        DictEnum.Entry(name = variant, value = null)

    private fun enactmentInstance(attendance: Boolean, disposition: String) = Struct.Instance(
        mapping = mapOf(
            "attendance" to attendance,
            "disposition" to dispositionEntry(disposition),
        )
    )

    @Test
    fun `decodes early-attendance enactment with Keep disposition`() {
        val instance = enactmentInstance(attendance = true, disposition = "Keep")

        val decoded: OnChainEarlyAttendanceEnactment = Scale.decode(instance)

        assertTrue(decoded.attendance)
        assertTrue(decoded.disposition is OnChainPlayerDisposition.Keep)
    }

    @Test
    fun `disposition variant names map to the sealed subtypes`() {
        val keep: OnChainEarlyAttendanceEnactment =
            Scale.decode(enactmentInstance(attendance = false, disposition = "Keep"))
        val kickable: OnChainEarlyAttendanceEnactment =
            Scale.decode(enactmentInstance(attendance = false, disposition = "ArchiveKickable"))
        val unkickable: OnChainEarlyAttendanceEnactment =
            Scale.decode(enactmentInstance(attendance = false, disposition = "ArchiveUnkickable"))

        assertTrue(keep.disposition is OnChainPlayerDisposition.Keep)
        assertTrue(kickable.disposition is OnChainPlayerDisposition.ArchiveKickable)
        assertTrue(unkickable.disposition is OnChainPlayerDisposition.ArchiveUnkickable)
    }

    @Test
    fun `decodes a full player with the enactment present`() {
        val instance = playerInstance(
            enactment = enactmentInstance(attendance = true, disposition = "ArchiveKickable")
        )

        val decoded: OnChainVideoGamePlayerInfo = Scale.decode(instance)

        assertEquals(7, decoded.firstGame.value)
        assertTrue(decoded.registered)
        assertTrue(decoded.sentReport)
        assertEquals(true, decoded.earlyAttendanceEnactment?.attendance)
        assertTrue(decoded.earlyAttendanceEnactment?.disposition is OnChainPlayerDisposition.ArchiveKickable)
        assertEquals(3.toByte(), decoded.yesPerson)
        assertEquals(1.toByte(), decoded.noNotPerson)
        assertEquals(64.toShort(), decoded.expectedMaxVoteWeight)
        assertEquals(2.toByte(), decoded.voteWeight)
        assertTrue(decoded.credibility is OnChainGamePlayerCredibility.Deposit)
    }

    @Test
    fun `decodes a full player with the enactment absent (Option None)`() {
        val instance = playerInstance(enactment = null)

        val decoded: OnChainVideoGamePlayerInfo = Scale.decode(instance)

        assertNull(decoded.earlyAttendanceEnactment)
        assertTrue(decoded.credibility is OnChainGamePlayerCredibility.Deposit)
    }

    @Test
    fun `rejects the OLD externallyRecognized shape — drift guard`() {
        // Pre-v0.9.0 runtime struct: had `externallyRecognized` + `zeroScore` and NO `disposition`.
        // Because the metadata path resolves fields BY NAME, the current model's required
        // `disposition` field is missing here, so decode must fail. This is the regression the
        // crash-loop taught us: a server-side rename the model didn't follow.
        val legacyEnactment = Struct.Instance(
            mapping = mapOf(
                "attendance" to true,
                "externallyRecognized" to true,
                "zeroScore" to false,
            )
        )

        val threw = runCatching {
            Scale.decode<OnChainEarlyAttendanceEnactment>(legacyEnactment)
        }.isFailure

        assertTrue("Expected decode to reject a struct missing the `disposition` field", threw)
    }

    private fun playerInstance(enactment: Struct.Instance?) = Struct.Instance(
        mapping = mapOf(
            "firstGame" to BigInteger.valueOf(7),
            "registered" to true,
            "sentReport" to true,
            "earlyAttendanceEnactment" to enactment,
            "yesPerson" to BigInteger.valueOf(3),
            "noNotPerson" to BigInteger.valueOf(1),
            "expectedMaxVoteWeight" to BigInteger.valueOf(64),
            "voteWeight" to BigInteger.valueOf(2),
            "credibility" to DictEnum.Entry(name = "Deposit", value = null),
        )
    )
}
