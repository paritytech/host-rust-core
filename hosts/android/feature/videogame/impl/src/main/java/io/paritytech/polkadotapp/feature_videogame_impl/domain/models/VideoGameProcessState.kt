package io.paritytech.polkadotapp.feature_videogame_impl.domain.models

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import kotlin.time.Duration

sealed interface VideoGameProcessState {
    /**
     * Pre-game state. While [preConnection] is non-null (the last [VideoGameTimings.PRE_CONNECTION_TIME]
     * seconds before [endsAt]), the session manager opens WebRTC channels to round-0 players ahead of
     * the [Round] transition so the host's video is already streaming when [HostingState.Introduction]
     * appears. Pre-warm peers are intentionally excluded from `VideoGameStateReader.players` — only the
     * local player renders during waiting.
     */
    data class WaitingRoom(
        val endsAt: Duration,
        val preConnection: PreConnection?
    ) : VideoGameProcessState

    /**
     * Active round. While [preConnection] is non-null (the last [VideoGameTimings.PRE_CONNECTION_TIME]
     * of this round), the session manager opens WebRTC channels to the next round's players ahead of
     * the transition. Pre-warm peers are intentionally excluded from `VideoGameStateReader.players`.
     */
    data class Round(
        val roundIndex: Int,
        val roundPlayers: List<AccountId>,
        val currentHost: AccountId,
        val hostingState: HostingState,
        val preConnection: PreConnection?
    ) : VideoGameProcessState

    data class Reporting(
        val endsAt: Duration
    ) : VideoGameProcessState

    data object Finished : VideoGameProcessState

    data class Error(val throwable: Throwable?) : VideoGameProcessState
}

sealed interface HostingState {
    val endsAt: Duration

    data class Introduction(override val endsAt: Duration) : HostingState

    data class Hosting(override val endsAt: Duration, val duration: Duration) : HostingState

    data class Ending(override val endsAt: Duration) : HostingState
}

data class PreConnection(val players: List<AccountId>)
