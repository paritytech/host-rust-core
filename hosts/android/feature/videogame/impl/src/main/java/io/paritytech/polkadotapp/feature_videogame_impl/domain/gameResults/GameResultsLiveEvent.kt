package io.paritytech.polkadotapp.feature_videogame_impl.domain.gameResults

/** Events from the post-open live phase of the results screen. */
sealed interface GameResultsLiveEvent {
    /** A late attestation NFT minted on chain; stream it to the shelf. */
    data class AttestationMinted(val hash: String) : GameResultsLiveEvent

    /** Attendance confirmed mid-stream: re-deliver [input], then push [padHashes] (real candidates before bonus fill). */
    data class UpgradedToPassed(
        val input: GameResultsInput,
        val padHashes: List<String>,
    ) : GameResultsLiveEvent
}
