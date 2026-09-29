package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.combineToPair
import io.paritytech.polkadotapp.common.utils.inBackground
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.common.utils.mapToSet
import io.paritytech.polkadotapp.common.utils.shareInBackground
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.GestureAcceptanceMessage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor.VideoGamePlayInteractor
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.HostingState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGamePlayer
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameStages
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.isConnected
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.audio.ConfettiSoundPlayer
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.isConnected
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGamePlayUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameTutorialState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameUiState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.calculateSugarLevel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.findHost
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.toUi
import io.paritytech.polkadotapp.feature_videogame_impl.service.VideoGameServiceController
import io.paritytech.polkadotapp.feature_videogame_impl.service.VideoGameStateReader
import kotlinx.collections.immutable.persistentSetOf
import kotlinx.collections.immutable.toImmutableList
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.flow.update
import javax.inject.Inject
import kotlin.time.Duration

@HiltViewModel
class VideoGamePlayViewModel @Inject constructor(
    private val router: VideoGameRouter,
    private val stateReader: VideoGameStateReader,
    private val interactor: VideoGamePlayInteractor,
    private val confettiSoundPlayer: ConfettiSoundPlayer,
    private val serviceController: VideoGameServiceController,
) : BaseViewModel(), VideoGamePlayContract {
    private val connectedPlayers = mutableMapOf<Int, MutableSet<AccountId>>()
    private var votingTooltipHasBeenShownThisGame = false

    private val gameSnapshot = stateReader.gameSnapshot
        .filterNotNull()
        .shareInBackground(SharingStarted.Eagerly)

    private val gameProcessState = gameSnapshot
        .map { it.processState }
        .shareInBackground(SharingStarted.Eagerly)

    private val gameTimeline = interactor.subscribeGameTimeline()
        .shareInBackground(SharingStarted.Eagerly)

    override val stages = gameSnapshot
        .map { it.stages }
        .stateInBackground(SharingStarted.Eagerly, VideoGameStages.Empty)

    private val playersState = combine(
        stateReader.players,
        gameProcessState
    ) { players, gameState ->
        PlayersState(
            gameState = gameState,
            players = players
        )
    }.shareInBackground()

    private val tooltipState = playersState
        .distinctUntilChangedBy { it.gameState }
        .transformLatest { state ->
            val gestureHintAccountId = getAccountIdForGestureHint(state)
            val showVotingTooltip = decideVotingTooltip(state)

            if (gestureHintAccountId != null) {
                delay(gestureTooltipDelay())
                emit(TooltipState(gestureHintAccountId = gestureHintAccountId))
            }

            if (showVotingTooltip) {
                delay(votingTooltipHalfwayDelay(hasGestureHint = gestureHintAccountId != null))
                emit(TooltipState(showVotingTooltip = true))
            }

            if (gestureHintAccountId == null && !showVotingTooltip) {
                emit(TooltipState())
            }
        }
        .shareInBackground()

    override val gameRenderState: StateFlow<VideoGamePlayUiState> = combine(
        gameProcessState,
        gameTimeline,
        stateReader.players,
        tooltipState,
        interactor.observeBannedPlayers()
    ) { processState, gameTime, peerPlayers, tooltip, banned ->
        val uiState = processState.toUi(gameTime)
        val isHostingPhase = uiState is VideoGameUiState.Hosting && !uiState.isEnding
        val currentHost = (processState as? VideoGameProcessState.Round)?.currentHost
        val players = peerPlayers
            .map { player ->
                // TODO: this is a workaround to address issue of inconsistent emissions
                // between players (based on old round host) and roundInfo (with a new host)
                // due to combine invoking lambda on every emission of both flows
                val correctedIsHost = currentHost?.let { player.accountId == it } ?: player.isHost
                player.copy(isHost = correctedIsHost).toUi(
                    showGestureHintTooltip = player.accountId == tooltip.gestureHintAccountId,
                    isBanned = player.accountId in banned,
                    isHostingPhase = isHostingPhase,
                )
            }
            .toImmutableList()
        VideoGamePlayUiState(state = uiState, players = players)
    }.stateInBackground(SharingStarted.Eagerly, VideoGamePlayUiState.Initial)

    override val votingTooltipVisible = tooltipState
        .map { it.showVotingTooltip }
        .distinctUntilChanged()
        .onEach { if (it) votingTooltipHasBeenShownThisGame = true }
        .stateInBackground(SharingStarted.Eagerly, false)

    override val noHostTooltipVisible = gameRenderState
        .map { it.isHostUnavailableDuringHosting() }
        .distinctUntilChanged()
        .transformLatest { hostUnavailable ->
            emit(hostUnavailable)
            if (hostUnavailable) {
                delay(VideoGameTimings.NO_HOST_TOOLTIP_DURATION)
                emit(false)
            }
        }
        .distinctUntilChanged()
        .stateInBackground(SharingStarted.Eagerly, false)

    override val selections = MutableStateFlow(persistentSetOf<AccountId>())

    private val myAcceptances = MutableStateFlow(persistentSetOf<AccountId>())

    override val sugarLevel = combine(
        myAcceptances,
        gameProcessState,
        stateReader.players,
    ) { acceptors, gameState, players ->
        val hostAccountId = (gameState as? VideoGameProcessState.Round)?.currentHost
        val localIsHost = players.find { it.isCurrentPlayer }?.isHost == true
        if (localIsHost) {
            0f
        } else {
            val eligibleNonHostCount = players.count { !it.isCurrentPlayer && !it.isHost }
            calculateSugarLevel(acceptors, hostAccountId, eligibleNonHostCount)
        }
    }.stateInBackground(SharingStarted.Eagerly, 0f)

    override val tutorialState = MutableStateFlow<VideoGameTutorialState>(VideoGameTutorialState.Hidden)

    init {
        openVotingWhenGameFinishes()

        gameSnapshot
            .onEach { hideTutorialOnGameStart(it.processState) }
            .launchIn(this)

        gameRenderState
            .onEach { data ->
                if (data.state is VideoGameUiState.HostReset) {
                    handleVotesIfNeeded(gameProcessState.first())
                }
            }
            .launchIn(this)

        gameProcessState
            .map { (it as? VideoGameProcessState.Round)?.currentHost }
            .distinctUntilChanged()
            .onEach { clearSelections() }
            .launchIn(this)

        combineToPair(gameProcessState, gameRenderState.map { it.players })
            .onEach { (state, players) -> updateConnectedPlayers(state, players) }
            .inBackground()
            .launchIn(this)

        observeIncomingAcceptances()
        observeSugarLevelForSound()
    }

    override fun collapse() {
        if (tutorialState.value is VideoGameTutorialState.Shown) {
            hideTutorial()
        } else if (!isInActiveState()) {
            router.back()
        }
    }

    override fun showTutorial() {
        tutorialState.value = VideoGameTutorialState.Shown
    }

    override fun hideTutorial() {
        tutorialState.value = VideoGameTutorialState.Hidden
    }

    override fun banPlayer(accountId: AccountId) = launchUnit {
        interactor.banPlayer(accountId)
        selections.update { it.remove(accountId) }
    }

    override fun unbanPlayer(accountId: AccountId) = launchUnit {
        interactor.unbanPlayer(accountId)
    }

    override fun selectPlayer(player: PlayerUiModel) {
        if (!player.isSelectable) return

        togglePlayerSelection(player)
    }

    override fun onCleared() {
        serviceController.stop()
        confettiSoundPlayer.release()
    }

    private fun isInActiveState(): Boolean = when (gameRenderState.value.state) {
        is VideoGameUiState.HostIntroduction,
        is VideoGameUiState.Hosting,
        is VideoGameUiState.HostReset -> true

        else -> false
    }

    private fun openVotingWhenGameFinishes() {
        launchUnit {
            gameRenderState.first { it.state is VideoGameUiState.Finished }
            router.openVoting()
        }
    }

    private fun observeIncomingAcceptances() {
        interactor.subscribeIncomingAcceptances()
            .onEach { message ->
                val currentRound = gameProcessState.first() as? VideoGameProcessState.Round ?: return@onEach
                if (message.roundIndex != currentRound.roundIndex) return@onEach

                when (message) {
                    is GestureAcceptanceMessage.Accept -> myAcceptances.update { it.add(message.acceptorAccountId) }
                    is GestureAcceptanceMessage.Unaccept -> myAcceptances.update { it.remove(message.acceptorAccountId) }
                }
            }
            .launchIn(this)
    }

    private fun observeSugarLevelForSound() {
        var lastPlayedSugar = 0f
        sugarLevel
            .onEach { level ->
                if (level > lastPlayedSugar && level > 0f) {
                    confettiSoundPlayer.play()
                }
                lastPlayedSugar = if (level <= 0f) 0f else level
            }
            .launchIn(this)
    }

    private fun gestureTooltipDelay(): Duration {
        return VideoGameTimings.HOST_ACTIVE_MINIMUM / 4
    }

    private fun votingTooltipHalfwayDelay(hasGestureHint: Boolean): Duration {
        return if (hasGestureHint) {
            VideoGameTimings.HOST_ACTIVE_MINIMUM / 4
        } else {
            VideoGameTimings.HOST_ACTIVE_MINIMUM / 2
        }
    }

    private fun getAccountIdForGestureHint(playersState: PlayersState): AccountId? {
        val gameState = playersState.gameState
        if (gameState !is VideoGameProcessState.Round) return null
        if (gameState.hostingState !is HostingState.Hosting) return null

        val host = playersState.players.find { it.isHost }
        if (host == null || !host.isConnected) return null

        val currentPlayer = playersState.players.find { it.isCurrentPlayer } ?: return null

        return when {
            currentPlayer.isHost && interactor.shouldShowShowGestureTooltip() -> {
                interactor.setShowGesturesTooltipShown()
                currentPlayer.accountId
            }

            !currentPlayer.isHost && interactor.shouldShowCopyGestureTooltip() -> {
                interactor.setCopyGesturesTooltipShown()
                host.accountId
            }

            else -> null
        }
    }

    private fun decideVotingTooltip(playersState: PlayersState): Boolean {
        val gameState = playersState.gameState
        if (gameState !is VideoGameProcessState.Round) return false
        if (gameState.roundIndex != 0) return false
        if (gameState.hostingState !is HostingState.Hosting) return false

        val host = playersState.players.find { it.isHost }
        if (host == null || !host.isConnected) return false

        return shouldShowVotingTooltip()
    }

    private fun shouldShowVotingTooltip(): Boolean {
        return !votingTooltipHasBeenShownThisGame
    }

    private fun VideoGamePlayUiState.isHostUnavailableDuringHosting(): Boolean {
        if (state !is VideoGameUiState.Hosting) return false

        val host = players.findHost()
        return host == null || host.connection != PlayerConnectionState.Connected
    }

    private fun VideoGamePlayer.toUi(
        showGestureHintTooltip: Boolean,
        isBanned: Boolean,
        isHostingPhase: Boolean,
    ) = PlayerUiModel(
        accountId = accountId,
        videoTrack = videoTrack,
        connection = connection,
        isCurrentPlayer = isCurrentPlayer,
        isHost = isHost,
        showGestureHintTooltip = showGestureHintTooltip,
        isBanned = isBanned,
        isSelectable = isHostingPhase && !isHost && !isCurrentPlayer && !isBanned && isConnected,
    )

    private fun updateConnectedPlayers(state: VideoGameProcessState, players: List<PlayerUiModel>) {
        if (state is VideoGameProcessState.Round) {
            val playersSet = connectedPlayers[state.roundIndex]
            val connectedPlayersSet = players.connected().mapToSet { it.accountId }.toMutableSet()

            if (playersSet != null) {
                playersSet.addAll(connectedPlayersSet)
            } else {
                connectedPlayers[state.roundIndex] = connectedPlayersSet
            }
        }
    }

    private suspend fun handleVotesIfNeeded(state: VideoGameProcessState) {
        if (state is VideoGameProcessState.Round) {
            when (state.hostingState) {
                is HostingState.Ending -> {
                    val roundConnectedPlayers = connectedPlayers[state.roundIndex].orEmpty()
                    interactor.trySaveVotes(state, roundConnectedPlayers, selections.value)
                }

                else -> Unit
            }
        }
    }

    private fun hideTutorialOnGameStart(state: VideoGameProcessState) {
        if (state !is VideoGameProcessState.WaitingRoom) {
            hideTutorial()
        }
    }

    private fun clearSelections() {
        selections.value = persistentSetOf()
        myAcceptances.value = persistentSetOf()
    }

    private fun togglePlayerSelection(player: PlayerUiModel) {
        val wasSelected = selections.value.contains(player.accountId)

        selections.update { set ->
            if (wasSelected) set.remove(player.accountId) else set.add(player.accountId)
        }

        launchUnit {
            val currentRound = gameProcessState.first() as? VideoGameProcessState.Round ?: return@launchUnit
            val localPlayer = stateReader.players.value.find { it.isCurrentPlayer } ?: return@launchUnit

            val message = if (wasSelected) {
                GestureAcceptanceMessage.Unaccept(currentRound.roundIndex, localPlayer.accountId)
            } else {
                GestureAcceptanceMessage.Accept(currentRound.roundIndex, localPlayer.accountId)
            }

            interactor.sendAcceptanceToPlayer(player.accountId, message)
        }
    }

    private fun List<PlayerUiModel>.connected() = filter { it.connection is PlayerConnectionState.Connected }

    private data class TooltipState(
        val gestureHintAccountId: AccountId? = null,
        val showVotingTooltip: Boolean = false,
    )

    private class PlayersState(
        val gameState: VideoGameProcessState,
        val players: List<VideoGamePlayer>
    )
}
