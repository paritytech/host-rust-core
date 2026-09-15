package io.paritytech.polkadotapp.feature_videogame_impl.service

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.x25519OrNull
import io.paritytech.polkadotapp.common.utils.InformationSize.Companion.kilobytes
import io.paritytech.polkadotapp.common.utils.compareTo
import io.paritytech.polkadotapp.feature_account_api.domain.model.SharedSecretDerivationDomain
import io.paritytech.polkadotapp.feature_statement_store_api.data.encryption.CommunicationEncryption
import io.paritytech.polkadotapp.feature_statement_store_api.domain.CommunicationSessionCreator
import io.paritytech.polkadotapp.feature_statement_store_api.domain.models.SessionAccount
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.GestureAcceptanceMessage
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ConnectionAttemptTracker
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.tools_media_connection_api.domain.GroupPeerConnection
import io.paritytech.polkadotapp.tools_media_connection_api.domain.PeerChannel
import io.paritytech.polkadotapp.tools_media_connection_api.domain.PeerConnectionLogger
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.MediaTracks
import io.paritytech.polkadotapp.tools_media_connection_api.domain.models.PeerChannelConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import timber.log.Timber

@OptIn(ExperimentalCoroutinesApi::class)
class VideoGamePeerChannel(
    private val groupConnection: GroupPeerConnection,
    private val communicationSessionCreator: CommunicationSessionCreator,
    private val communicationEncryptionFactory: CommunicationEncryption.Factory,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val connectionAttemptTracker: ConnectionAttemptTracker,
    private val chainRegistry: ChainRegistry,
    private val localAccountId: AccountId,
    private val remoteAccountId: AccountId,
    private val gameIndex: GameIndex,
    scope: CoroutineScope
) : CoroutineScope by scope {
    companion object {
        private const val VIDEO_GAME_ROOM_PIN = "video_game_room"
        private val MAX_STATEMENT_SIZE = 1.kilobytes
        private const val GESTURE_ACCEPTANCE_USE_CASE = "video_game_gesture_acceptance"
    }

    private val currentPeer = MutableStateFlow<PeerChannel?>(null)

    val connectionState = currentPeer.flatMapLatest { peer ->
        peer?.connectionState ?: flowOf(PeerChannelConnectionState.New)
    }

    val videoTrack = currentPeer.flatMapLatest { peer ->
        peer?.mediaTracks ?: flowOf(MediaTracks())
    }.map { it.remoteVideoTrack }

    val incomingAcceptances: Flow<GestureAcceptanceMessage> = currentPeer.flatMapLatest { peer ->
        val transport = peer?.dataTransport ?: return@flatMapLatest emptyFlow()
        transport.subscribeMessages(GESTURE_ACCEPTANCE_USE_CASE)
            .mapNotNull { data ->
                runCatching { GestureAcceptanceMessage.decode(data) }
                    .onFailure { Timber.w(it, "Failed to decode gesture acceptance from $remoteAccountId") }
                    .getOrNull()
            }
    }

    suspend fun sendAcceptance(message: GestureAcceptanceMessage) {
        val transport = currentPeer.value?.dataTransport ?: return
        if (!transport.isOpen()) return

        transport.send(GESTURE_ACCEPTANCE_USE_CASE, GestureAcceptanceMessage.encode(message))
    }

    fun start() {
        launch { connectionMonitor() }
    }

    fun dispose() {
        currentPeer.value?.let { disposePeer(it) }
        cancel()
    }

    private suspend fun connectionMonitor() {
        val signaling = createSignaling()
        if (signaling == null) {
            Timber.w("[VideoGame] game=${gameIndex.value} no signaling for peer $remoteAccountId — connection aborted")
            return
        }

        val isInitiator = localAccountId.value.compareTo(remoteAccountId.value, unsigned = true) < 0

        val lastOfferId = connectionAttemptTracker.getLastOfferId(gameIndex, remoteAccountId)

        if (lastOfferId != null) {
            signaling.sendReconnected(lastOfferId)
        }

        Timber.i("[VideoGame] game=${gameIndex.value} connecting peer $remoteAccountId initiator=$isInitiator")
        currentPeer.value = createAndStartPeer(signaling, isInitiator)

        signaling.subscribeReconnected().collect { offerIdToDispose ->
            Timber.i("Received reconnected signal with offerId: $offerIdToDispose")
            if (signaling.getOfferId() == offerIdToDispose) {
                currentPeer.value?.let { disposePeer(it) }
                signaling.reset()
                currentPeer.value = createAndStartPeer(signaling, isInitiator)
            }
        }
    }

    private fun createAndStartPeer(
        signaling: VideoGamePeerChannelSignaling,
        isInitiator: Boolean
    ): PeerChannel {
        val logger = PeerConnectionLogger { signaling.getOfferId() }
        val channel = groupConnection.createPeer(signaling, isInitiator, logger)
        channel.startConnection()
        return channel
    }

    private fun disposePeer(peer: PeerChannel) {
        currentPeer.value = null
        groupConnection.disposePeer(peer)
    }

    private suspend fun createSignaling(): VideoGamePeerChannelSignaling? {
        val peerPublicKey = videoGameRepository.getCommunicationIdentifier(
            chainId = chainRegistry.peopleChain().id,
            accountId = remoteAccountId
        ).mapCatching {
            it?.x25519OrNull() ?: error("Peer has no usable chat encryption key")
        }.onFailure { Timber.e(it, "Failed to get communication identifier") }
            .getOrNull() ?: return null

        val encryption = runCatching {
            communicationEncryptionFactory.create(
                SharedSecretDerivationDomain.CANDIDATE,
                peerPublicKey
            )
        }.onFailure { Timber.e(it, "Invalid communication identifier of peer $remoteAccountId") }
            .getOrNull() ?: return null

        val communicationSession = communicationSessionCreator.createSession(
            scope = this,
            localAccount = SessionAccount.Local(
                accountId = localAccountId,
                pin = VIDEO_GAME_ROOM_PIN
            ),
            remoteAccount = SessionAccount.Remote(
                accountId = remoteAccountId,
                pin = VIDEO_GAME_ROOM_PIN,
                publicKey = peerPublicKey
            ),
            encryption = encryption,
            maxStatementSize = MAX_STATEMENT_SIZE
        )

        return VideoGamePeerChannelSignaling(
            session = communicationSession,
            gameIndex = gameIndex,
            onOfferIdDetermined = { offerId ->
                connectionAttemptTracker.saveOfferId(gameIndex, remoteAccountId, offerId)
            }
        )
    }
}
