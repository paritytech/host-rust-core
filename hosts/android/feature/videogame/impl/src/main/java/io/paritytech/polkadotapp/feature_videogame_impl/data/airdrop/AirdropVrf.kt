package io.paritytech.polkadotapp.feature_videogame_impl.data.airdrop

import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop.AirdropProof
import kotlinx.serialization.Serializable

/**
 * The `airdrop` argument on the `Game::sign_up_*` calls — the player's lottery proof. Encoded by
 * NAME against runtime metadata (variant names `Account`/`Alias`, camelCase fields), matching the
 * runtime `game::types::AirdropVrf`.
 */
@Serializable
sealed class AirdropVrf {
    /**
     * Non-recognized account player: sr25519 VRF over the 32-byte event id. The runtime variant is
     * the 1-field tuple `Account(VrfSignature)`, so sp-core `VrfSignature`'s fields (32-byte
     * `pre_output` + 64-byte `proof`) sit directly on the variant — a wrapper level fails
     * extrinsic encoding.
     */
    @Serializable
    class Account(
        val preOutput: DataByteArray,
        val proof: DataByteArray,
    ) : AirdropVrf()

    /** Recognized person: bandersnatch ring membership proof at the current on-chain ring revision. */
    @Serializable
    class Alias(
        val proof: DataByteArray,
        val ringIndex: Int,
        val revision: Int,
    ) : AirdropVrf()
}

/** Maps the domain proof to the SCALE call argument — the domain↔wire boundary stays in data. */
fun AirdropProof.toAirdropVrf(): AirdropVrf = when (this) {
    is AirdropProof.Account ->
        AirdropVrf.Account(preOutput = preOutput.toDataByteArray(), proof = proof.toDataByteArray())

    is AirdropProof.Alias ->
        AirdropVrf.Alias(proof = proof.toDataByteArray(), ringIndex = ringIndex, revision = revision)
}
