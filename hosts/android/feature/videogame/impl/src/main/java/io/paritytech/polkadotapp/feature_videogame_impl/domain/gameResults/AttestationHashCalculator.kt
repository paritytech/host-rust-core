package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

import io.novasama.substrate_sdk_android.hash.Hasher.blake2b256
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.BinaryScale
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.annotations.EnumIndex
import io.novasama.substrate_sdk_android.koltinx_serialization_scale.binary.annotations.FixedLength
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainAccountOrPerson
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToByteArray

/**
 * Recomputes the deterministic attestation-NFT id that pallet-game mints, so we can
 * match minted NFTs against the peers we were grouped with. Mirrors `compute_nft`:
 * `(b"polkadot-pop-game", game_index: u32, round: u8, attester, attestee)` SCALE-encoded
 * then blake2_256. The result is value-comparable for set membership against minted hashes.
 */
object AttestationHashCalculator {
    fun computeHash(
        gameIndex: GameIndex,
        round: Int,
        attester: OnChainAccountOrPerson,
        attestee: OnChainAccountOrPerson
    ): DataByteArray {
        // Concatenation order and widths are positional SCALE — gameIndex is u32 (Int),
        // round is u8 (Byte), the prefix is raw fixed bytes (no length prefix).
        val preimage = DOMAIN_PREFIX +
            BinaryScale.encodeToByteArray(gameIndex.value) +
            BinaryScale.encodeToByteArray(round.toByte()) +
            BinaryScale.encodeToByteArray(attester.toScale()) +
            BinaryScale.encodeToByteArray(attestee.toScale())

        return preimage.blake2b256().toDataByteArray()
    }

    /**
     * Visual-only filler id for the pass-case shelf:
     * `blake2b256("dim2-bonus" + gameIndex: u32 + player + slot: u8)`. Never matched against
     * chain state (the web side derives rarity from the hash); must stay byte-identical to iOS.
     */
    fun computeBonusHash(
        gameIndex: GameIndex,
        player: OnChainAccountOrPerson,
        slot: Int
    ): DataByteArray {
        val preimage = BONUS_PREFIX +
            BinaryScale.encodeToByteArray(gameIndex.value) +
            BinaryScale.encodeToByteArray(player.toScale()) +
            BinaryScale.encodeToByteArray(slot.toByte())

        return preimage.blake2b256().toDataByteArray()
    }

    // The chain's AccountOrPerson enum: variant byte + the raw 32-byte key (no length prefix).
    // @FixedLength drops the Vec<u8> length so the SCALE encoding matches the preimage.
    @Serializable
    private sealed interface AccountOrPersonScale {
        @Serializable
        @EnumIndex(0)
        data class Account(@FixedLength(32) val accountId: ByteArray) : AccountOrPersonScale

        @Serializable
        @EnumIndex(1)
        data class Person(@FixedLength(32) val alias: ByteArray) : AccountOrPersonScale
    }

    private fun OnChainAccountOrPerson.toScale(): AccountOrPersonScale = when (this) {
        is OnChainAccountOrPerson.Account -> AccountOrPersonScale.Account(accountId.value)
        is OnChainAccountOrPerson.Person -> AccountOrPersonScale.Person(alias.value)
    }

    private val DOMAIN_PREFIX = "polkadot-pop-game".encodeToByteArray()
    private val BONUS_PREFIX = "dim2-bonus".encodeToByteArray()
}
