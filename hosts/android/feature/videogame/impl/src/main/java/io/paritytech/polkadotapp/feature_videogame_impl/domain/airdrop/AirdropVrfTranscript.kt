package io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop

import io.paritytech.polkadotapp.sr25519_vrf.Sr25519VrfTranscriptItem

/**
 * The merlin transcript recipe the People Chain airdrop signs, mirroring the runtime's
 * `indiv_pallet_airdrop::vrf::transcript_for_event`: root label `"pop:airdrop"`, then
 * `domain = label ++ eventId` and `signer = sr25519 public key`. A byte-order or ordering slip here
 * verifies fine locally but fails on-chain — covered by `airdrop_shape_matches_previous_hardcoded`
 * in the `sr25519-vrf` crate.
 */
object AirdropVrfTranscript {
    val LABEL: ByteArray = "pop:airdrop".toByteArray(Charsets.US_ASCII)

    fun items(eventId: ByteArray, publicKey: ByteArray): List<Sr25519VrfTranscriptItem> = listOf(
        Sr25519VrfTranscriptItem(label = DOMAIN_LABEL, value = LABEL + eventId),
        Sr25519VrfTranscriptItem(label = SIGNER_LABEL, value = publicKey),
    )

    private val DOMAIN_LABEL = "domain".toByteArray(Charsets.US_ASCII)
    private val SIGNER_LABEL = "signer".toByteArray(Charsets.US_ASCII)
}
