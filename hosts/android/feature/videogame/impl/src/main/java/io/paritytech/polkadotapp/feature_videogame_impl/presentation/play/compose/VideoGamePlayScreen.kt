@file:OptIn(ExperimentalMotionApi::class)

package io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.layoutId
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.zIndex
import androidx.constraintlayout.compose.ConstraintSet
import androidx.constraintlayout.compose.ExperimentalMotionApi
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import io.paritytech.polkadotapp.common.domain.model.AccountId
import io.paritytech.polkadotapp.common.domain.model.DataByteArray
import io.paritytech.polkadotapp.common.domain.model.toDataByteArray
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.presentation.formatters.time.TimeFormatter
import io.paritytech.polkadotapp.common.utils.calculateProgress
import io.paritytech.polkadotapp.design.theme.PolkadotTheme
import io.paritytech.polkadotapp.design.utils.KeepScreenOn
import io.paritytech.polkadotapp.design.utils.LockScreenOrientation
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.webrtc.PlayerConnectionState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameStages
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.components.DiagonalStripeBackground
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.compose.theme.GameColors
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.VideoGamePlayContract
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components.*
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components.waitingRoom.WaitingRoomBackground
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.components.waitingRoom.WaitingRoomScreen
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.compose.constraints.*
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.PlayerUiModel
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameTutorialState
import io.paritytech.polkadotapp.feature_videogame_impl.presentation.play.models.VideoGameUiState
import kotlinx.collections.immutable.ImmutableList
import kotlinx.collections.immutable.ImmutableSet
import kotlinx.collections.immutable.persistentListOf
import kotlinx.collections.immutable.persistentSetOf
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

@Composable
fun VideoGamePlayScreen(contract: VideoGamePlayContract) {
    val data by contract.gameRenderState.collectAsStateWithLifecycle()
    val stages by contract.stages.collectAsStateWithLifecycle()
    val selections by contract.selections.collectAsStateWithLifecycle()
    val sugarLevel by contract.sugarLevel.collectAsStateWithLifecycle()
    val votingTooltipVisible by contract.votingTooltipVisible.collectAsStateWithLifecycle()
    val noHostTooltipVisible by contract.noHostTooltipVisible.collectAsStateWithLifecycle()
    val tutorialState by contract.tutorialState.collectAsStateWithLifecycle()
    KeepScreenOn()
    LockScreenOrientation()

    BackHandler {
        contract.collapse()
    }

    VideoGamePlayScreenInternal(
        state = data.state,
        tutorialState = tutorialState,
        players = data.players,
        stages = stages,
        onCollapse = contract::collapse,
        onOpenTutorialClicked = contract::showTutorial,
        onCloseTutorialClicked = contract::hideTutorial,
        selections = selections,
        sugarLevel = sugarLevel,
        votingTooltipVisible = votingTooltipVisible,
        noHostTooltipVisible = noHostTooltipVisible,
        onPlayerSelected = contract::selectPlayer,
        onBanPlayer = contract::banPlayer,
        onUnbanPlayer = contract::unbanPlayer
    )
}

@Composable
private fun VideoGamePlayScreenInternal(
    state: VideoGameUiState,
    tutorialState: VideoGameTutorialState,
    players: ImmutableList<PlayerUiModel>,
    stages: VideoGameStages,
    onCollapse: () -> Unit,
    onOpenTutorialClicked: () -> Unit,
    onCloseTutorialClicked: () -> Unit,
    selections: ImmutableSet<AccountId>,
    sugarLevel: Float,
    onPlayerSelected: (PlayerUiModel) -> Unit,
    votingTooltipVisible: Boolean,
    noHostTooltipVisible: Boolean,
    onBanPlayer: (AccountId) -> Unit,
    onUnbanPlayer: (AccountId) -> Unit
) {
    ProvideGameFrameTicker {
        Box(
            modifier = Modifier.fillMaxSize()
        ) {
            when (state) {
                is VideoGameUiState.Initial,
                is VideoGameUiState.Finished,
                is VideoGameUiState.Error -> Unit

                is VideoGameUiState.WaitingRoom -> {
                    WaitingRoomScreen(
                        state = state,
                        onCollapse = onCollapse,
                        onOpenTutorial = onOpenTutorialClicked,
                    )
                }

                is VideoGameUiState.Connecting,
                is VideoGameUiState.HostIntroduction,
                is VideoGameUiState.Hosting,
                is VideoGameUiState.HostReset -> {
                    val isCurrentPlayerHost = remember(players) {
                        players.find { it.isCurrentPlayer }?.isHost ?: false
                    }

                    val constraintConfig = remember(state, players) {
                        val duration = state.transitionDuration
                        ConstraintConfig(
                            constraintSet = createConstraintSet(state, players),
                            animateChangesSpec = tween(durationMillis = duration.inWholeMilliseconds.toInt()),
                            snap = duration == Duration.ZERO
                        )
                    }

                    WaitingRoomBackground(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(GameColors.backgroundPrimary),
                        isVisible = state is VideoGameUiState.Connecting,
                    )

                    DiagonalStripeBackground(
                        modifier = Modifier.fillMaxSize(),
                        isVisible = state !is VideoGameUiState.Connecting,
                        isIntroAnimating = state is VideoGameUiState.HostIntroduction
                    )

                    GameMotionLayout(
                        modifier = Modifier
                            .fillMaxSize(),
                        config = constraintConfig
                    ) {
                        Box(modifier = Modifier.layoutId(LeftAnchorLayoutId))
                        Box(modifier = Modifier.layoutId(RightAnchorLayoutId))

                        players.forEach { player ->
                            key(player.accountId) {
                                val cellModifier = Modifier
                                    .zIndex(player.zIndex)
                                    .layoutId(player.referenceId)

                                if (state is VideoGameUiState.Connecting) {
                                    ConnectionPlayerCell(
                                        modifier = cellModifier,
                                        player = player,
                                        revealCamera = state.camerasRevealed,
                                    )
                                } else {
                                    PlayerCell(
                                        modifier = cellModifier,
                                        state = state,
                                        player = player,
                                        onClick = { onPlayerSelected(player) },
                                        isSelected = player.accountId in selections,
                                        onBanToggle = {
                                            if (player.isBanned) {
                                                onUnbanPlayer(player.accountId)
                                            } else {
                                                onBanPlayer(player.accountId)
                                            }
                                        },
                                        sugarLevel = if (player.isCurrentPlayer) sugarLevel else 0f
                                    )
                                }
                            }
                        }

                        HostingHeader(
                            modifier = Modifier
                                .zIndex(10f)
                                .systemBarsPadding()
                                .layoutId(HostingIntroductionHeaderLayoutId),
                            isCurrentPlayerHost = isCurrentPlayerHost
                        )

                        HostingFooter(
                            modifier = Modifier
                                .zIndex(10f)
                                .navigationBarsPadding()
                                .layoutId(HostingIntroductionFooterLayoutId),
                            isCurrentPlayerHost = isCurrentPlayerHost
                        )

                        HowToPlayButton(
                            modifier = Modifier
                                .statusBarsPadding()
                                .layoutId(HowToPlayButtonLayoutId),
                            onClick = onOpenTutorialClicked
                        )

                        ConnectingCountdown(
                            modifier = Modifier
                                .navigationBarsPadding()
                                .padding(bottom = PolkadotTheme.spacings.large)
                                .layoutId(ConnectingCountdownLayoutId),
                            state = state
                        )

                        SubroundProgressBar(
                            modifier = Modifier
                                .navigationBarsPadding()
                                .padding(
                                    start = PolkadotTheme.spacings.large,
                                    end = PolkadotTheme.spacings.large,
                                    bottom = PolkadotTheme.spacings.large
                                )
                                .layoutId(HostingProgressBarLayoutId),
                            currentSubround = (stages.currentStage - 1).coerceAtLeast(0),
                            totalSubrounds = stages.stagesCount,
                            subroundProgress = when (state) {
                                is VideoGameUiState.Hosting -> calculateProgress(state.duration, state.timeLeft)
                                is VideoGameUiState.HostReset -> 1f
                                else -> 0f
                            }
                        )
                    }

                    VideoGameVotingTooltip(
                        modifier = Modifier
                            .align(Alignment.TopCenter)
                            .padding(top = PolkadotTheme.spacings.small)
                            .statusBarsPadding(),
                        visible = votingTooltipVisible
                    )

                    HostUnavailableTooltip(
                        modifier = Modifier
                            .align(Alignment.TopCenter)
                            .padding(top = PolkadotTheme.spacings.small)
                            .statusBarsPadding(),
                        visible = noHostTooltipVisible
                    )
                }
            }

            VideoGameTutorialOverlay(tutorialState, onCloseTutorialClicked)
        }
    }
}

private fun createConstraintSet(
    state: VideoGameUiState,
    players: ImmutableList<PlayerUiModel>,
) = ConstraintSet {
    val (anchorLeft, anchorRight) = setupGridAnchors()

    when (state) {
        is VideoGameUiState.Connecting -> {
            createConnectingConstraints(players, anchorLeft, anchorRight, state.camerasRevealed)
        }

        is VideoGameUiState.HostIntroduction -> {
            createHostIntroductionConstraints(players)
        }

        is VideoGameUiState.Hosting -> {
            createHostingConstraints(players, anchorLeft, anchorRight)
        }

        VideoGameUiState.HostReset -> {
            createHostResetConstraints(players, anchorLeft, anchorRight)
        }

        is VideoGameUiState.WaitingRoom,
        VideoGameUiState.Initial,
        VideoGameUiState.Finished -> Unit

        VideoGameUiState.Error -> Unit // TODO: should not happen, but if it does, we need to create new layout
    }
}

@Preview
@Composable
private fun ConnectingPreview() {
    PolkadotTheme {
        CompositionLocalProvider(
            LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current)
        ) {
            VideoGamePlayScreenInternal(
                state = VideoGameUiState.Connecting(timeLeft = 5.seconds),
                tutorialState = VideoGameTutorialState.Hidden,
                players = persistentListOf(
                    previewConnectingPlayer(0, PlayerConnectionState.Connected, isCurrentPlayer = true),
                    previewConnectingPlayer(1, PlayerConnectionState.Connecting),
                    previewConnectingPlayer(2, PlayerConnectionState.Connected),
                    previewConnectingPlayer(3, PlayerConnectionState.Disconnected),
                    previewConnectingPlayer(4, PlayerConnectionState.Connecting),
                    previewConnectingPlayer(5, PlayerConnectionState.Disconnected)
                ),
                stages = VideoGameStages.Empty,
                onCollapse = { },
                onOpenTutorialClicked = { },
                onCloseTutorialClicked = { },
                selections = persistentSetOf(),
                sugarLevel = 0f,
                onPlayerSelected = { },
                votingTooltipVisible = false,
                noHostTooltipVisible = false,
                onBanPlayer = {},
                onUnbanPlayer = {}
            )
        }
    }
}

private fun previewConnectingPlayer(
    seed: Byte,
    connection: PlayerConnectionState,
    isCurrentPlayer: Boolean = false,
) = PlayerUiModel(
    accountId = byteArrayOf(seed).toDataByteArray(),
    videoTrack = null,
    connection = connection,
    isHost = false,
    isCurrentPlayer = isCurrentPlayer,
    showGestureHintTooltip = false,
    isBanned = false,
    isSelectable = false,
)

@Preview
@Composable
private fun TooltipsPreview() {
    val accountId1 = byteArrayOf(0).toDataByteArray()
    val accountId2 = byteArrayOf(1).toDataByteArray()

    PolkadotTheme {
        CompositionLocalProvider(
            LocalTimeFormatter provides TimeFormatter.mocked(LocalContext.current)
        ) {
            Box(
                modifier = Modifier
                    .background(GameColors.backgroundPrimary)
                    .fillMaxSize()
            ) {
                VideoGamePlayScreenInternal(
                    state = VideoGameUiState.Hosting(1.minutes, 1.minutes, false),
                    tutorialState = VideoGameTutorialState.Hidden,
                    players = persistentListOf(
                        PlayerUiModel(accountId1, null, PlayerConnectionState.Disconnected, true, true, false, false, false),
                        PlayerUiModel(accountId2, null, PlayerConnectionState.Disconnected, false, false, false, true, false)
                    ),
                    stages = VideoGameStages.Empty,
                    onCollapse = { },
                    onOpenTutorialClicked = { },
                    onCloseTutorialClicked = { },
                    selections = persistentSetOf(DataByteArray.empty()),
                    sugarLevel = 0f,
                    onPlayerSelected = { },
                    votingTooltipVisible = false,
                    noHostTooltipVisible = true,
                    onBanPlayer = {},
                    onUnbanPlayer = {}
                )
            }
        }
    }
}
