package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_videogame_api.domain.models.UpcomingGameStart
import io.paritytech.polkadotapp.feature_videogame_api.domain.usecase.UpcomingGameStartUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.isWaitingRoomAvailable
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameProcessState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameSnapshot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameStages
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.isWaitingRoomJoinable
import io.paritytech.polkadotapp.feature_videogame_impl.domain.timeline.VideoGameTimelineService
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameRegistrationStageUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameReportSubmittedUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.service.VideoGameStateReader
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration

@Singleton
internal class WeeklyGamePillStateProducer @Inject constructor(
    private val stateReader: VideoGameStateReader,
    private val timelineService: VideoGameTimelineService,
    private val upcomingGameStartUseCase: UpcomingGameStartUseCase,
    private val registrationStageUseCase: VideoGameRegistrationStageUseCase,
    private val reportSubmittedUseCase: VideoGameReportSubmittedUseCase,
) {
    context(scope: ComputationalScope)
    fun pillState(): Flow<VideoGamePillState> = combine(
        stateReader.gameSnapshot,
        timelineService.subscribeTimeline(),
        upcomingGameStartUseCase.subscribe(),
        registrationStageUseCase.subscribe(),
        reportSubmittedUseCase.observeReportSubmitted(),
    ) { snapshot, gameTime, upcomingGameStart, registrationStage, reportSubmitted ->
        createPillState(snapshot, gameTime, upcomingGameStart, registrationStage, reportSubmitted)
    }

    private fun createPillState(
        snapshot: VideoGameSnapshot?,
        gameTime: Duration?,
        upcomingGameStart: UpcomingGameStart?,
        registrationStage: VideoGameRegistrationStage,
        reportSubmitted: Boolean,
    ): VideoGamePillState {
        if (registrationStage !is VideoGameRegistrationStage.Registered) return VideoGamePillState.Hidden
        if (snapshot == null) return preSessionPillState(upcomingGameStart)

        return when (val processState = snapshot.processState) {
            is VideoGameProcessState.WaitingRoom -> {
                if (isWaitingRoomJoinable(registrationStage, processState, gameTime)) {
                    waitingCountdown(processState.endsAt, gameTime)
                } else {
                    VideoGamePillState.Hidden
                }
            }

            is VideoGameProcessState.Round -> inProgress(snapshot.stages)
            is VideoGameProcessState.Reporting -> {
                if (reportSubmitted) VideoGamePillState.Hidden else VideoGamePillState.Shown.Review
            }
            VideoGameProcessState.Finished -> VideoGamePillState.Hidden
            is VideoGameProcessState.Error -> VideoGamePillState.Hidden
        }
    }

    private fun waitingCountdown(endsAt: Duration, gameTime: Duration): VideoGamePillState.Shown.WaitingCountdown {
        val secondsLeft = (endsAt - gameTime).coerceAtLeast(Duration.ZERO).inWholeSeconds
        return VideoGamePillState.Shown.WaitingCountdown(secondsLeft)
    }

    private fun preSessionPillState(
        upcomingGameStart: UpcomingGameStart?,
    ): VideoGamePillState {
        return when (upcomingGameStart) {
            is UpcomingGameStart.Current -> {
                if (!upcomingGameStart.isWaitingRoomAvailable) return VideoGamePillState.Hidden
                val secondsLeft = upcomingGameStart.timeLeftUntilStart
                    .coerceAtLeast(Duration.ZERO)
                    .inWholeSeconds
                VideoGamePillState.Shown.WaitingCountdown(secondsLeft)
            }
            is UpcomingGameStart.Next, null -> VideoGamePillState.Hidden
        }
    }

    private fun inProgress(stages: VideoGameStages): VideoGamePillState.Shown.InProgress {
        return VideoGamePillState.Shown.InProgress(
            currentRound = stages.currentStage,
            totalRounds = stages.stagesCount,
        )
    }
}
