package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import io.paritytech.polkadotapp.common.R
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.formatters.time.LocalTimeFormatter
import io.paritytech.polkadotapp.common.utils.currentTimestampFlow
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatPreview
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatPreview.Custom.BadgeStyle
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatPreviewDataProvider
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatPreviewDelegate
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatPreviewRenderer
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomPreviewData
import io.paritytech.polkadotapp.feature_chats_api.domain.model.Order
import io.paritytech.polkadotapp.feature_videogame_api.domain.models.UpcomingGameStart
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_api.domain.usecase.UpcomingGameStartUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.isStartingSoon
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.registrationIsPossible
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameJourneyItem
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.WeeklyGameChatPreview
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.lastNonFutureGame
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameJourneyUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameRegistrationStageUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.onStart
import javax.inject.Inject
import kotlin.time.Duration.Companion.minutes

class WeeklyGameChatPreviewDelegate @Inject constructor(
    override val provider: WeeklyGameChatPreviewDataProvider,
    override val renderer: WeeklyGameChatPreviewRenderer
) : CustomChatPreviewDelegate<WeeklyGameChatPreview>

class WeeklyGameChatPreviewDataProvider @Inject constructor(
    private val videoGameProgressUseCase: VideoGamesProgressUseCase,
    private val videoGameJourneyUseCase: VideoGameJourneyUseCase,
    private val upcomingGameStartUseCase: UpcomingGameStartUseCase,
    private val videoGameRegistrationStageUseCase: VideoGameRegistrationStageUseCase
) : CustomChatPreviewDataProvider<WeeklyGameChatPreview> {
    companion object {
        private val TICK_INTERVAL = 1.minutes
    }

    context(scope: ComputationalScope)
    override fun provide(): Flow<ChatPreview.Custom<WeeklyGameChatPreview>?> {
        // Emit the pinned idle preview immediately so Polkadot Prizes stays on top from the
        // first frame, even before the 5 upstream flows below have all produced their initial
        // value. The combine result supersedes this once data loads.
        return combine(
            currentTimestampFlow(TICK_INTERVAL),
            videoGameProgressUseCase.videoGamesProgressFlow(),
            videoGameJourneyUseCase(),
            upcomingGameStartUseCase.subscribe(),
            videoGameRegistrationStageUseCase.subscribe(),
        ) { currentTimestamp, videoGameProgress, journey, upcomingGame, registrationStage ->
            // The Polkadot Prizes chat stays pinned even in idle states: when there's no
            // game-specific payload, we still emit a Custom with Order.PinToTop and
            // CustomPreviewData.FromMessage so the row renders the last message but keeps
            // the top-of-list position.
            when {
                upcomingGame is UpcomingGameStart.Current && registrationStage.registrationIsPossible() -> {
                    pinnedPreview(
                        data = WeeklyGameChatPreview.NewGameAnnounced(upcomingGame.startsAt),
                        badgeStyle = BadgeStyle.NOTIFICATION,
                    )
                }

                upcomingGame is UpcomingGameStart.Current && registrationStage is VideoGameRegistrationStage.Registered -> {
                    if (upcomingGame.isStartingSoon(currentTimestamp)) {
                        pinnedPreview(
                            data = WeeklyGameChatPreview.GameStarting,
                            badgeStyle = BadgeStyle.NOTIFICATION,
                        )
                    } else {
                        pinnedPreview(
                            data = WeeklyGameChatPreview.Registered(upcomingGame.startsAt),
                            badgeStyle = BadgeStyle.NONE,
                        )
                    }
                }

                videoGameProgress is VideoGamesProgress.PersonhoodReached -> {
                    pinnedPreview(
                        data = WeeklyGameChatPreview.PeerReached,
                        badgeStyle = BadgeStyle.NOTIFICATION,
                    )
                }

                // Otherwise falls to idlePinnedPreview() which renders the prior game's outcome from DB.
                videoGameProgress is VideoGamesProgress.FinalGameProcessing -> {
                    gamePendingPreview()
                }

                // Transient state after final-game submission, before recognition lands.
                videoGameProgress is VideoGamesProgress.ReadyToReachPersonhood -> {
                    gamePendingPreview()
                }

                videoGameProgress is VideoGamesProgress.PlayingGames -> {
                    // Avoid prior-outcome flash while progress has updated but journey hasn't rebuilt.
                    if (videoGameProgress.pendingGameResults) {
                        gamePendingPreview()
                    } else {
                        when (journey.lastNonFutureGame()?.status) {
                            VideoGameJourneyItem.Status.PENDING -> gamePendingPreview()

                            VideoGameJourneyItem.Status.SUCCESSFUL -> pinnedPreview(
                                data = WeeklyGameChatPreview.GameSuccessful(videoGameProgress.score.gamesLeft),
                                badgeStyle = BadgeStyle.NONE,
                            )

                            VideoGameJourneyItem.Status.FAILED -> pinnedPreview(
                                data = WeeklyGameChatPreview.GameFailed(videoGameProgress.score.gamesLeft),
                                badgeStyle = BadgeStyle.NOTIFICATION,
                            )

                            VideoGameJourneyItem.Status.FUTURE,
                            null -> idlePinnedPreview()
                        }
                    }
                }

                else -> idlePinnedPreview()
            }
        }.onStart { emit(idlePinnedPreview()) }
    }

    private fun gamePendingPreview() = pinnedPreview(
        data = WeeklyGameChatPreview.GamePending,
        badgeStyle = BadgeStyle.NONE,
    )

    private fun pinnedPreview(
        data: WeeklyGameChatPreview,
        badgeStyle: BadgeStyle,
    ) = ChatPreview.Custom(
        order = Order.PinToTop,
        data = CustomPreviewData.RendererPayload(data),
        badgeStyle = badgeStyle,
    )

    /**
     * Keeps Polkadot Prizes at the top even when no game is active: pins by order but tells
     * ChatEngine to render the last bot message instead of a custom payload.
     */
    private fun idlePinnedPreview(): ChatPreview.Custom<WeeklyGameChatPreview> = ChatPreview.Custom(
        order = Order.PinToTop,
        data = CustomPreviewData.FromMessage,
        badgeStyle = BadgeStyle.NONE,
    )
}

class WeeklyGameChatPreviewRenderer @Inject constructor() : CustomChatPreviewRenderer<WeeklyGameChatPreview> {
    @Composable
    override fun formatChatPreview(data: WeeklyGameChatPreview): Result<String> {
        val text = when (data) {
            is WeeklyGameChatPreview.NewGameAnnounced -> {
                val timeFormatter = LocalTimeFormatter.current
                stringResource(R.string.chat_bot_weekly_game_chat_preview_game_announced, timeFormatter.formatDateTime(data.timestamp))
            }

            is WeeklyGameChatPreview.Registered -> {
                val timeFormatter = LocalTimeFormatter.current
                stringResource(R.string.chat_bot_weekly_game_chat_preview_game_registered, timeFormatter.formatDateTime(data.timestamp))
            }

            is WeeklyGameChatPreview.GameStarting -> {
                stringResource(R.string.chat_bot_weekly_game_chat_preview_game_starting)
            }

            is WeeklyGameChatPreview.GamePending -> {
                stringResource(R.string.chat_bot_weekly_game_chat_preview_game_processing)
            }

            is WeeklyGameChatPreview.GameSuccessful -> {
                stringResource(R.string.chat_bot_weekly_game_chat_preview_game_success, data.gamesLeft)
            }

            is WeeklyGameChatPreview.GameFailed -> {
                stringResource(R.string.chat_bot_weekly_game_chat_preview_game_failed, data.gamesLeft)
            }

            is WeeklyGameChatPreview.PeerReached -> {
                stringResource(R.string.chat_bot_weekly_game_chat_preview_game_peer_reached)
            }
        }

        return Result.success(text)
    }
}
