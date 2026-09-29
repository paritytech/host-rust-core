package io.paritytech.polkadotapp.feature_videogame_impl.data.gameResults

/**
 * Inbound events from the game-results webview. Informational except [RequestDisplayName] and
 * [UsernameAvailabilityNeeded], which expect a paired native reply.
 */
sealed interface FlowEvent {
    data object Ready : FlowEvent
    data object ResultsShown : FlowEvent
    data object PrizeDrawStarted : FlowEvent
    data class PrizeDrawComplete(val won: Boolean) : FlowEvent
    data class NftRevealStarted(val count: Int) : FlowEvent
    data object NftRevealComplete : FlowEvent
    data object UsernameClaimRequested : FlowEvent
    data object RequestDisplayName : FlowEvent

    /** Webview needs username availability for [name] (base form) but hasn't received one. */
    data class UsernameAvailabilityNeeded(val name: String) : FlowEvent

    /** Recoverable webview-side error worth logging. Phases today: `boot_timeout`, `assets`. */
    data class Error(val phase: String, val detail: String?) : FlowEvent

    data object Complete : FlowEvent
    data class Unknown(val type: String) : FlowEvent
}
