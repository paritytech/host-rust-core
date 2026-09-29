package io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop

/**
 * Domain representation of the airdrop sign-up proof. The data layer maps this to the SCALE
 * `AirdropVrf` call argument — the wire type stays out of domain.
 */
sealed class AirdropProof {
    /** sr25519 VRF for a non-recognized account player: 32-byte pre-output + 64-byte proof. */
    class Account(val preOutput: ByteArray, val proof: ByteArray) : AirdropProof()

    /** Bandersnatch ring proof for a recognized person at the given on-chain ring revision. */
    class Alias(val proof: ByteArray, val ringIndex: Int, val revision: Int) : AirdropProof()
}
