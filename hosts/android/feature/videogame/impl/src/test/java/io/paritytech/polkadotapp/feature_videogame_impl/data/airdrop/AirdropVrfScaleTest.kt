package io.paritytech.polkadotapp.feature_videogame_impl.data.airdrop

import io.novasama.substrate_sdk_android.koltinx_serialization_scale.Scale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.decode
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.DictEnum
import io.novasama.substrate_sdk_android.runtime.definitions.types.composite.Struct
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertTrue
import org.junit.Test
import java.math.BigInteger

/**
 * Conformance guard for the `AirdropVrf` sign-up call argument. Drives the real by-NAME metadata
 * codec over the `DictEnum.Entry` / `Struct.Instance` tree the call path produces, so a variant
 * rename (`Account`/`Alias`) or a field-name drift (`preOutput`, `ringIndex`, `revision`) fails here
 * instead of as a rejected extrinsic on-chain. Mirrors `AirdropApiScaleDecodeTest`.
 */
class AirdropVrfScaleTest {
    @Test
    fun `account variant is the flat sp-core VrfSignature - no wrapper level`() {
        // Runtime: `Account(VrfSignature)` is a 1-field tuple variant, so the variant value IS the
        // signature struct. A nested `{signature: {...}}` level fails extrinsic encoding
        // ("is not a valid instance of <Option>") — caught on-device in game 464.
        val instance = DictEnum.Entry(
            name = "Account",
            value = Struct.Instance(
                mapping = mapOf(
                    "preOutput" to ByteArray(32) { 1 },
                    "proof" to ByteArray(64) { 2 },
                )
            ),
        )

        val decoded: AirdropVrf = Scale.decode(instance)

        decoded as AirdropVrf.Account
        assertEquals(32, decoded.preOutput.value.size)
        assertTrue(decoded.proof.value.contentEquals(ByteArray(64) { 2 }))
    }

    @Test
    fun `alias variant maps proof, ring index and revision`() {
        val instance = DictEnum.Entry(
            name = "Alias",
            value = Struct.Instance(
                mapping = mapOf(
                    "proof" to ByteArray(785) { 3 },
                    "ringIndex" to BigInteger.valueOf(7),
                    "revision" to BigInteger.valueOf(4),
                )
            ),
        )

        val decoded: AirdropVrf = Scale.decode(instance)

        decoded as AirdropVrf.Alias
        assertEquals(785, decoded.proof.value.size)
        assertEquals(7, decoded.ringIndex)
        assertEquals(4, decoded.revision)
    }
}
