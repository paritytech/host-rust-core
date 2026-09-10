package io.paritytech.polkadotapp.feature_videogame_impl.service

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.common.presentation.subscribeIsForeground
import io.paritytech.polkadotapp.common.utils.childScope
import io.paritytech.polkadotapp.feature_statement_store_api.data.encryption.CommunicationEncryption
import io.paritytech.polkadotapp.feature_statement_store_api.domain.CommunicationSessionCreator
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.getCurrentActiveGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.GestureAcceptanceMessage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ConnectionAttemptTracker
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.telemetry.GameDashboardTelemetryRepository
import io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor.RecordGamePlayersUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.HostingState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGamePlayer
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameSnapshot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.requiresLocalCamera
import io.paritytech.polkadotapp.feature_videogame_impl.domain.telemetry.GameDashboardTelemetryEmitter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.PlayingAccountUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.helpers.PlayerFrameCapturer
import io.paritytech.polkadotapp.tools_media_connection_api.domain.GroupPeerConnection
import io.paritytech.polkadotapp.tools_media_connection_api.domain.PeerChannelFactory
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.MediaConfiguration
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.PeerChannelConnectionState
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.VideoDegradationPreference
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.VideoEncodingProfile
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.VideoTrack
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

class VideoGameSessionManager @Inject constructor(
    private val peerChannelFactory: PeerChannelFactory,
    private val communicationSessionCreatorFactory: CommunicationSessionCreator.Factory,
    private val communicationEncryptionFactory: CommunicationEncryption.Factory,
    private val playingAccountUseCase: PlayingAccountUseCase,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val connectionAttemptTracker: ConnectionAttemptTracker,
    private val gameInfoSyncService: VideoGameInfoSyncService,
    private val videoGameStateHolder: VideoGameStateHolder,
    private val recordGamePlayersUseCase: RecordGamePlayersUseCase,
    private val frameCapturer: PlayerFrameCapturer,
    private val chainRegistry: ChainRegistry,
    private val appLifecycleObserver: AppLifecycleObserver,
    private val gameDashboardTelemetry: GameDashboardTelemetryEmitter,
) {
    private val peerChannels = MutableStateFlow<Map<AccountId, VideoGamePeerChannel>>(emptyMap())

    private val videoProfile = VideoEncodingProfile(
        captureTargetHeight = 480,
        captureFps = 24,
        maxBitrateBps = 600_000,
        degradationPreference = VideoDegradationPreference.MAINTAIN_FRAMERATE
    )

    context(scope: ComputationalScope)
    suspend fun startSession() {
        Timber.i("[VideoGame] startSession: resolving playing account")
        val playingAccount = playingAccountUseCase.getPlayingAccount()
        val localAccountId = playingAccount.accountIdIn(chainRegistry.peopleChain())
        val communicationSessionCreator = communicationSessionCreatorFactory.create(playingAccount)

        Timber.i("[VideoGame] startSession: creating group peer connection")
        val connection = peerChannelFactory.createGroupConnection(
            mediaConfiguration = MediaConfiguration.VideoOnly(
                initialCameraEnabled = false,
                videoProfile = videoProfile,
            ),
            scope = scope
        )

        Timber.i("[VideoGame] startSession: initializing local media (camera)")
        connection.initLocalMedia()

        combine(
            appLifecycleObserver.subscribeIsForeground(),
            videoGameStateHolder.gameSnapshot
                .filterNotNull()
                .map { it.processState.requiresLocalCamera() }
                .distinctUntilChanged(),
        ) { foregrounded, cameraNeeded -> foregrounded && cameraNeeded }
            .distinctUntilChanged()
            .onEach { connection.setLocalVideoEnabled(it) }
            .launchIn(scope)

        val sessionInfo = SessionInfo(
            groupConnection = connection,
            communicationSessionCreator = communicationSessionCreator,
            localAccountId = localAccountId
        )

        Timber.i("[VideoGame] startSession: observing game state for account=$localAccountId")
        videoGameStateHolder.gameSnapshot
            .filterNotNull()
            .distinctUntilChanged()
            .onEach { snapshot -> handleGameStateChange(sessionInfo, snapshot) }
            .launchIn(scope)

        observePlayers(localAccountId, connection)
        startReportingTelemetry(localAccountId)
    }

    fun endSession() {
        Timber.i("[VideoGame] endSession: disposing ${peerChannels.value.size} peer channel(s)")
        peerChannels.value.forEach { (_, peerChannel) -> peerChannel.dispose() }
        peerChannels.value = emptyMap()
    }

    fun subscribeIncomingAcceptances(): Flow<GestureAcceptanceMessage> =
        peerChannels.flatMapLatest { channels ->
            channels.values.map { it.incomingAcceptances }.merge()
        }

    suspend fun sendAcceptanceToPlayer(targetAccountId: AccountId, message: GestureAcceptanceMessage) {
        peerChannels.value[targetAccountId]?.sendAcceptance(message)
    }

    context(scope: ComputationalScope)
    private suspend fun handleGameStateChange(sessionInfo: SessionInfo, snapshot: VideoGameSnapshot) {
        Timber.i("[VideoGame] game=${snapshot.gameIndex.value} session state=${snapshot.processState::class.simpleName}")
        when (val state = snapshot.processState) {
            is VideoGameProcessState.WaitingRoom -> {
                val players = state.preConnection?.players.orEmpty()
                setConnectedPlayers(sessionInfo, snapshot.gameIndex, players)
            }

            is VideoGameProcessState.Round -> {
                Timber.i("[VideoGame] game=${snapshot.gameIndex.value} round=${state.roundIndex} roundPlayers=${state.roundPlayers.size} preConnect=${state.preConnection?.players?.size ?: 0}")
                val players = state.roundPlayers + state.preConnection?.players.orEmpty()
                setConnectedPlayers(sessionInfo, snapshot.gameIndex, players)
                handleFrameCaptureIfNeeded(snapshot, state)
            }

            is VideoGameProcessState.Reporting -> {
                val gameInfo = gameInfoSyncService.getCurrentActiveGameInfo()
                recordGamePlayersUseCase.invoke(gameInfo)
            }

            is VideoGameProcessState.Finished,
            is VideoGameProcessState.Error -> Unit
        }
    }

    context(scope: ComputationalScope)
    private fun setConnectedPlayers(
        sessionInfo: SessionInfo,
        gameIndex: GameIndex,
        allPlayers: List<AccountId>
    ) {
        val remotePlayers = allPlayers - sessionInfo.localAccountId

        val current = peerChannels.value.keys
        val toAdd = remotePlayers.toSet() - current
        val toRemove = current - remotePlayers.toSet()

        if (toAdd.isNotEmpty() || toRemove.isNotEmpty()) {
            Timber.i("[VideoGame] game=${gameIndex.value} peers added=${toAdd.size} removed=${toRemove.size} activeRemote=${remotePlayers.size}")
        }

        toRemove.forEach { accountId ->
            peerChannels.value[accountId]?.dispose()
        }

        val newChannels = toAdd.associateWith { accountId ->
            VideoGamePeerChannel(
                groupConnection = sessionInfo.groupConnection,
                communicationSessionCreator = sessionInfo.communicationSessionCreator,
                communicationEncryptionFactory = communicationEncryptionFactory,
                videoGameRepository = videoGameRepository,
                connectionAttemptTracker = connectionAttemptTracker,
                chainRegistry = chainRegistry,
                localAccountId = sessionInfo.localAccountId,
                remoteAccountId = accountId,
                gameIndex = gameIndex,
                scope = scope.childScope(true)
            ).also { it.start() }
        }

        peerChannels.update { map ->
            (map - toRemove) + newChannels
        }
    }

    context(scope: ComputationalScope)
    private fun handleFrameCaptureIfNeeded(snapshot: VideoGameSnapshot, state: VideoGameProcessState.Round) {
        if (state.hostingState !is HostingState.Hosting) return

        scope.launch {
            delay(PlayerFrameCapturer.CAPTURE_DELAY)

            val hostAccountId = state.currentHost
            val videoTrack = videoGameStateHolder.players.value
                .find { it.accountId == hostAccountId }
                ?.videoTrack ?: return@launch

            val bitmap = videoTrack.captureFrame() ?: return@launch

            frameCapturer.capture(
                gameIndex = snapshot.gameIndex,
                accountId = hostAccountId,
                bitmap = bitmap
            )
        }
    }

    context(scope: ComputationalScope)
    private fun observePlayers(
        currentPlayerAccountId: AccountId,
        groupConnection: GroupPeerConnection
    ) {
        combine(
            subscribePeerPlayers(),
            groupConnection.localVideoTrack,
            videoGameStateHolder.gameSnapshot.filterNotNull()
        ) { peerPlayers, localVideoTrack, snapshot ->
            val currentHost = (snapshot.processState as? VideoGameProcessState.Round)?.currentHost

            val playerAccountIds = when (val gameState = snapshot.processState) {
                is VideoGameProcessState.WaitingRoom -> gameState.preConnection?.players ?: listOf(currentPlayerAccountId)
                is VideoGameProcessState.Round -> gameState.roundPlayers
                is VideoGameProcessState.Reporting,
                is VideoGameProcessState.Finished,
                is VideoGameProcessState.Error -> emptyList()
            }

            playerAccountIds.map { accountId ->
                val isCurrentPlayer = accountId == currentPlayerAccountId
                val peer = if (isCurrentPlayer) null else peerPlayers[accountId]

                VideoGamePlayer(
                    accountId = accountId,
                    videoTrack = if (isCurrentPlayer) localVideoTrack else peer?.videoTrack,
                    connection = if (isCurrentPlayer) PlayerConnectionState.Connected else (peer?.connection ?: PlayerConnectionState.Disconnected),
                    isCurrentPlayer = isCurrentPlayer,
                    isHost = accountId == currentHost
                )
            }
        }
            .onEach { players ->
                Timber.i("[VideoGame] players rendered=${players.size} connected=${players.count { it.connection == PlayerConnectionState.Connected }} withVideo=${players.count { it.videoTrack != null }}")
                videoGameStateHolder.updatePlayers(players)
            }
            .launchIn(scope)
    }

    context(scope: ComputationalScope)
    private fun startReportingTelemetry(localAccountId: AccountId) {
        combine(
            gameInfoSyncService.subscribeCurrentActiveGameInfo().filterNotNull(),
            subscribePeerStates()
        ) { gameInfo, states ->
            buildReportingPayload(localAccountId, states, gameInfo)
        }
            .distinctUntilChanged()
            .onEach { payload ->
                if (payload.isEmpty()) {
                    Timber.d("Dashboard reporting: skipping — no rounds yet")
                    return@onEach
                }
                Timber.d("Dashboard reporting: ${payload.size} rounds")
                gameDashboardTelemetry.submitReporting(localAccount = localAccountId, rounds = payload)
            }
            .catch { Timber.w(it, "Dashboard reporting flow failed") }
            .launchIn(scope)
    }

    private fun buildReportingPayload(
        localAccountId: AccountId,
        states: Map<AccountId, PeerChannelConnectionState>,
        gameInfo: VideoGameInfo
    ): List<List<GameDashboardTelemetryRepository.PeerEntry>> {
        val rounds = (gameInfo.state as? VideoGameState.InProgress)?.rounds.orEmpty()
        return rounds.map { round ->
            round.players
                .filter { it != localAccountId }
                .map { player ->
                    GameDashboardTelemetryRepository.PeerEntry(
                        accountId = player,
                        state = states[player] ?: PeerChannelConnectionState.Disconnected
                    )
                }
        }
    }

    private fun subscribePeerStates(): Flow<Map<AccountId, PeerChannelConnectionState>> =
        peerChannels.flatMapLatest { channels ->
            if (channels.isEmpty()) {
                flowOf(emptyMap())
            } else {
                combine(
                    channels.entries.map { (accountId, channel) ->
                        channel.connectionState.map { state -> accountId to state }
                    }
                ) { pairs -> pairs.toMap() }
            }
        }

    private fun subscribePeerPlayers(): Flow<Map<AccountId, PeerPlayerData>> =
        peerChannels.flatMapLatest { channels ->
            if (channels.isEmpty()) {
                flowOf(emptyMap())
            } else {
                combine(
                    channels.entries.map { (accountId, channel) ->
                        combine(
                            channel.videoTrack,
                            channel.connectionState
                        ) { videoTrack, connectionState ->
                            PeerPlayerData(
                                accountId = accountId,
                                videoTrack = videoTrack,
                                connection = connectionState.toPlayerConnectionState()
                            )
                        }
                    }
                ) { array -> array.associateBy { it.accountId } }
            }
        }

    private class PeerPlayerData(
        val accountId: AccountId,
        val videoTrack: VideoTrack?,
        val connection: PlayerConnectionState
    )

    private class SessionInfo(
        val groupConnection: GroupPeerConnection,
        val communicationSessionCreator: CommunicationSessionCreator,
        val localAccountId: AccountId
    )
}

private fun PeerChannelConnectionState.toPlayerConnectionState(): PlayerConnectionState = when (this) {
    PeerChannelConnectionState.New,
    PeerChannelConnectionState.Connecting -> PlayerConnectionState.Connecting

    PeerChannelConnectionState.Connected -> PlayerConnectionState.Connected
    PeerChannelConnectionState.Disconnected,
    PeerChannelConnectionState.Closed -> PlayerConnectionState.Disconnected

    PeerChannelConnectionState.Failed -> PlayerConnectionState.Failed(Exception("Peer connection failed"))
}
