package io.paritytech.polkadotapp.feature_videogame_impl.service

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.GestureAcceptanceMessage
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGamePlayer
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameSnapshot
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

interface VideoGameStateReader {
    /**
     * The current snapshot of the game-state machine — phase, stages, and round info
     * derived from the on-chain `OnChainVideoGameInfo` and the local clock.
     *
     * `null` while the service has not yet computed a snapshot (boot / pre-connect).
     */
    val gameSnapshot: StateFlow<VideoGameSnapshot?>

    /**
     * Players visible to the UI for the current round.
     *
     * Inside a round this lists exactly the [VideoGameProcessState.Round.roundPlayers]
     * (one [VideoGamePlayer] per `accountId`) decorated with local view fields:
     * `videoTrack`, `connection`, `isHost`, `isCurrentPlayer`.
     *
     * Outside an active round:
     *  - [VideoGameProcessState.WaitingRoom] — the local player only, until the connection
     *    stage opens (the final [VideoGameTimings.CONNECTION_STAGE_DURATION] before the game
     *    starts), at which point the round-0 roster (`preConnection.players`, including the
     *    local player) is surfaced so the connection-stage grid can render.
     *  - [VideoGameProcessState.Reporting] / [VideoGameProcessState.Finished] /
     *    [VideoGameProcessState.Error] — empty.
     *
     * This is narrower than the live peer-channel pool. During the final
     * [VideoGameTimings.PRE_CONNECTION_TIME] of each *round* the session manager opens
     * peer channels for the next round's players ahead of the transition so they are
     * already connected when the new round begins; those in-round pre-warm peers are
     * intentionally excluded from this flow so the UI grid only renders the
     * round-active roster.
     */
    val players: StateFlow<List<VideoGamePlayer>>

    val isSessionRunning: Boolean
}

interface GestureAcceptanceChannel {
    fun subscribeIncomingAcceptances(): Flow<GestureAcceptanceMessage>
    suspend fun sendAcceptanceToPlayer(targetAccountId: AccountId, message: GestureAcceptanceMessage)
}

interface VideoGameStateHolder : VideoGameStateReader {
    fun updatePlayers(players: List<VideoGamePlayer>)

    fun setSessionManager(sessionManager: VideoGameSessionManager)

    fun endSession()
}

interface VideoGameSnapshotWriter {
    fun updateGameSnapshot(snapshot: VideoGameSnapshot?)
}

fun VideoGameStateReader.isInWaitingRoom(): Boolean =
    gameSnapshot.value?.processState is VideoGameProcessState.WaitingRoom
