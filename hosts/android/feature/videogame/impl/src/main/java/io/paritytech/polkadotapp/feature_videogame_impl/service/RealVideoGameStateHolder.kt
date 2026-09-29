package io.paritytech.polkadotapp.feature_videogame_impl.service

import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.GestureAcceptanceMessage
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGamePlayer
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameSnapshot
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.emptyFlow
import kotlinx.coroutines.flow.flatMapLatest
import javax.inject.Inject
import javax.inject.Singleton

@OptIn(ExperimentalCoroutinesApi::class)
@Singleton
class RealVideoGameStateHolder @Inject constructor() :
    VideoGameStateHolder,
    VideoGameSnapshotWriter,
    GestureAcceptanceChannel {
    override val gameSnapshot = MutableStateFlow<VideoGameSnapshot?>(null)
    override val players = MutableStateFlow<List<VideoGamePlayer>>(emptyList())

    private val sessionManagerFlow = MutableStateFlow<VideoGameSessionManager?>(null)

    override val isSessionRunning: Boolean
        get() = sessionManagerFlow.value != null

    override fun setSessionManager(sessionManager: VideoGameSessionManager) {
        sessionManagerFlow.value = sessionManager
    }

    override fun subscribeIncomingAcceptances(): Flow<GestureAcceptanceMessage> {
        return sessionManagerFlow.flatMapLatest { manager ->
            manager?.subscribeIncomingAcceptances() ?: emptyFlow()
        }
    }

    override suspend fun sendAcceptanceToPlayer(targetAccountId: AccountId, message: GestureAcceptanceMessage) {
        val manager = sessionManagerFlow.value
        manager?.sendAcceptanceToPlayer(targetAccountId, message)
    }

    override fun updateGameSnapshot(snapshot: VideoGameSnapshot?) {
        gameSnapshot.value = snapshot
    }

    override fun updatePlayers(players: List<VideoGamePlayer>) {
        this.players.value = players
    }

    override fun endSession() {
        players.value = emptyList()
        sessionManagerFlow.value = null
    }
}
