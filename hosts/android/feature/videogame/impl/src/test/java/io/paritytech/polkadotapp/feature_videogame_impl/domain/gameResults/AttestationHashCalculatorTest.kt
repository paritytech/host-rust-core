package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import io.novasama.substrate_sdk_android.hash.Hasher.blake2b256
import io.paritytech.polkadotapp.bandersnatch_crypto.BandersnatchAlias
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import junit.framework.TestCase.assertEquals
import junit.framework.TestCase.assertFalse
import junit.framework.TestCase.assertTrue
import org.junit.Test

class AttestationHashCalculatorTest {
    private fun account(seed: Byte) =
        OnChainAccountOrPerson.Account(ByteArray(32) { seed }.toDataByteArray())

    private val attester = account(1)
    private val attestee = account(2)

    private fun hash(
        gameIndex: Int = 7,
        round: Int = 3,
        attester: OnChainAccountOrPerson = this.attester,
        attestee: OnChainAccountOrPerson = this.attestee
    ) = AttestationHashCalculator.computeHash(GameIndex(gameIndex), round, attester, attestee)

    @Test
    fun `produces a 32-byte hash`() {
        assertEquals(32, hash().value.size)
    }

    @Test
    fun `account hash matches the known compute_nft preimage`() {
        // Pins the exact preimage so the @FixedLength SCALE encoding can't silently drift:
        // blake2_256("polkadot-pop-game" + u32 game + u8 round + (0x00 + 32B) + (0x00 + 32B)).
        val expected = (
            "polkadot-pop-game".toByteArray() +
                byteArrayOf(7, 0, 0, 0) + byteArrayOf(3) +
                byteArrayOf(0) + ByteArray(32) { 1 } +
                byteArrayOf(0) + ByteArray(32) { 2 }
            ).blake2b256().toDataByteArray()

        assertEquals(expected, hash())
    }

    @Test
    fun `is deterministic for the same inputs`() {
        assertTrue(hash() == hash())
    }

    @Test
    fun `changes with round, game index, attester and attestee`() {
        val base = hash()
        assertFalse(base == hash(round = 4))
        assertFalse(base == hash(gameIndex = 8))
        assertFalse(base == hash(attester = account(9)))
        assertFalse(base == hash(attestee = account(9)))
    }

    @Test
    fun `account and person variants of the same key hash differently`() {
        val bytes = ByteArray(32) { 5 }
        val asAccount = OnChainAccountOrPerson.Account(bytes.toDataByteArray())
        val asPerson = OnChainAccountOrPerson.Person(BandersnatchAlias(bytes))
        assertFalse(hash(attester = asAccount) == hash(attester = asPerson))
    }

    @Test
    fun `bonus hash is a deterministic 32-byte hash`() {
        val first = AttestationHashCalculator.computeBonusHash(GameIndex(7), attestee, slot = 3)
        val second = AttestationHashCalculator.computeBonusHash(GameIndex(7), attestee, slot = 3)

        assertEquals(32, first.value.size)
        assertTrue(first == second)
    }

    @Test
    fun `bonus hash changes with game index, player and slot`() {
        val base = AttestationHashCalculator.computeBonusHash(GameIndex(7), attestee, slot = 3)

        assertFalse(base == AttestationHashCalculator.computeBonusHash(GameIndex(8), attestee, slot = 3))
        assertFalse(base == AttestationHashCalculator.computeBonusHash(GameIndex(7), account(9), slot = 3))
        assertFalse(base == AttestationHashCalculator.computeBonusHash(GameIndex(7), attestee, slot = 4))
    }

    @Test
    fun `bonus hash differs from the attestation hash`() {
        assertFalse(hash() == AttestationHashCalculator.computeBonusHash(GameIndex(7), attestee, slot = 3))
    }
}
