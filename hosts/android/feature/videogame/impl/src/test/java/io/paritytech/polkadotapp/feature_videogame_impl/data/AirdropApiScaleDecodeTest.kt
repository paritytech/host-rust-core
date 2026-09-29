package io.paritytech.polkadotapp.feature_videogame_impl.data

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decode
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.DictEnum
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.Struct
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainActiveEvent
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropPrize
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropRegistrationEntry
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAirdropStatus
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAssetMetadata
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.firstGeneralIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.totalParticipants
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertNull
import junit.framework.TestCase.assertTrue
import org.junit.Test
import java.math.BigInteger

/**
 * Conformance guard for the pallet-airdrop SCALE types in [AirdropApi]. Like the `Player` decode
 * test, this drives the real by-NAME metadata codec (`koltinx_serialization_scale.Scale`) over a
 * reconstructed `Struct.Instance` / `DictEnum.Entry` tree — the exact intermediate the storage
 * query path produces — so a field rename or a sealed-variant name drift on the Kotlin model
 * fails here instead of silently nulling the prize draw at runtime.
 */
class AirdropApiScaleDecodeTest {
    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

    // assetId is an XCM Location {parents, interior}; the Asset Hub asset id rides in its
    // GeneralIndex junction. This also guards that the xcm MultiLocationSerializer composes inside
    // the by-NAME airdrop decode.
    private fun assetIdInstance() = Struct.Instance(
        mapping = mapOf(
            "parents" to BigInteger.ZERO,
            "interior" to DictEnum.Entry(
                name = "X2",
                value = listOf(
                    DictEnum.Entry(name = "PalletInstance", value = BigInteger.valueOf(50)),
                    DictEnum.Entry(name = "GeneralIndex", value = BigInteger.valueOf(1984)),
                ),
            ),
        )
    )

    private fun prizeInstance() = Struct.Instance(
        mapping = mapOf(
            "assetId" to assetIdInstance(),
            "assetAmount" to BigInteger.valueOf(200_000_000_000L),
            "maxWinners" to BigInteger.valueOf(20),
            "winnerCap" to BigInteger.valueOf(100),
        )
    )

    @Test
    fun `decodes asset metadata`() {
        val instance = Struct.Instance(
            mapping = mapOf(
                "deposit" to BigInteger.valueOf(1_000),
                // String fields decode from a ByteArray intermediate on the metadata path.
                "name" to "Web3 Token".toByteArray(),
                "symbol" to "W3T".toByteArray(),
                "decimals" to BigInteger.valueOf(10),
                "isFrozen" to false,
            )
        )

        val decoded: OnChainAssetMetadata = Scale.decode(instance)

        assertEquals("W3T", decoded.symbol)
        assertEquals(10.toByte(), decoded.decimals)
    }

    @Test
    fun `decodes the airdrop prize`() {
        val decoded: OnChainAirdropPrize = Scale.decode(prizeInstance())

        assertEquals(BigInteger.valueOf(1984), decoded.assetId.firstGeneralIndex())
        assertEquals(BigInteger.valueOf(200_000_000_000L), decoded.assetAmount)
        assertEquals(20, decoded.maxWinners)
        assertEquals(100, decoded.winnerCap)
    }

    @Test
    fun `decodes a full active event with a data-carrying status variant`() {
        val instance = Struct.Instance(
            mapping = mapOf(
                "id" to bytes(1, 2, 3, 4),
                "info" to Struct.Instance(
                    mapping = mapOf(
                        "prize" to prizeInstance(),
                        "registrationStarts" to BigInteger.valueOf(1_000),
                        "drawTime" to BigInteger.valueOf(2_000),
                        "endTime" to BigInteger.valueOf(3_000),
                    )
                ),
                "status" to DictEnum.Entry(
                    name = "Registering",
                    value = Struct.Instance(mapping = mapOf("totalParticipants" to BigInteger.valueOf(42))),
                ),
            )
        )

        val decoded: OnChainActiveEvent = Scale.decode(instance)

        assertEquals(2_000L, decoded.info.drawTime)
        assertEquals(BigInteger.valueOf(1984), decoded.info.prize.assetId.firstGeneralIndex())
        assertTrue(decoded.status is OnChainAirdropStatus.Registering)
        assertEquals(42, decoded.status.totalParticipants)
    }

    @Test
    fun `status variant names map to the sealed subtypes`() {
        val scheduled: OnChainAirdropStatus = Scale.decode(DictEnum.Entry(name = "Scheduled", value = null))
        val drawWinners: OnChainAirdropStatus = Scale.decode(
            DictEnum.Entry(
                name = "DrawWinners",
                value = Struct.Instance(
                    mapping = mapOf(
                        "totalParticipants" to BigInteger.valueOf(10),
                        "effectiveWinners" to BigInteger.valueOf(5),
                        "winnersAdded" to BigInteger.valueOf(5),
                        "fromWinnerKey" to bytes(9, 9),
                    )
                ),
            )
        )

        assertTrue(scheduled is OnChainAirdropStatus.Scheduled)
        assertNull(scheduled.totalParticipants)
        assertTrue(drawWinners is OnChainAirdropStatus.DrawWinners)
        assertEquals(10, drawWinners.totalParticipants)
    }

    @Test
    fun `registration entry variants map to the sealed subtypes`() {
        val account: OnChainAirdropRegistrationEntry = Scale.decode(
            DictEnum.Entry(
                name = "Account",
                value = Struct.Instance(mapping = mapOf("accountId" to bytes(7, 7, 7))),
            )
        )
        val alias: OnChainAirdropRegistrationEntry = Scale.decode(
            DictEnum.Entry(
                name = "Alias",
                value = Struct.Instance(mapping = mapOf("participantOrigin" to bytes(8, 8))),
            )
        )

        assertTrue(account is OnChainAirdropRegistrationEntry.Account)
        assertTrue(alias is OnChainAirdropRegistrationEntry.Alias)
    }
}
