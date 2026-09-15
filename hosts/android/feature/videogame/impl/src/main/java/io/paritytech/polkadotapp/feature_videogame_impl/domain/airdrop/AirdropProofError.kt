package io.paritytech.polkadotapp.feature_videogame_impl.domain.airdrop

/**
 * A proof-construction failure for an airdrop-scheduled game. The caller treats these as
 * best-effort (see `resolveAirdropProof`): it logs and registers WITHOUT the airdrop rather than
 * blocking the player from the game — the only cost is forfeiting this game's lottery ticket.
 * (Parity with iOS: a bonus-feature failure must never block game registration.)
 */
sealed class AirdropProofError(message: String) : Exception(message) {
    object MissingRingRevision : AirdropProofError("current on-chain ring revision is unavailable")
    object NotRingIncluded : AirdropProofError("recognized player has no included ring position")
}
