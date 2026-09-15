package io.paritytech.polkadotapp.feature_videogame_impl.domain.bot

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatOpenHandler
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.isWaitingRoomJoinable
import io.paritytech.polkadotapp.feature_videogame_impl.domain.timeline.VideoGameTimelineService
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameRegistrationStageUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.service.VideoGameStateReader
import io.paritytech.polkadotapp.feature_videogame_impl.utils.VideoGameLaunchCoordinator
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds

internal class WeeklyGameOpenHandler @Inject constructor(
    private val stateReader: VideoGameStateReader,
    private val registrationStageUseCase: VideoGameRegistrationStageUseCase,
    private val timelineService: VideoGameTimelineService,
    private val launchCoordinator: VideoGameLaunchCoordinator,
) : CustomChatOpenHandler {
    override suspend fun handleOpen(): Boolean {
        if (!isJoinable()) return false
        launchCoordinator.openOrLaunchGame()
        return true
    }

    // Any failure or slow read falls back to opening the chat feed, so the tap never hangs or dies.
    private suspend fun isJoinable(): Boolean =
        runCancellableCatching {
            withTimeoutOrNull(JOINABLE_CHECK_TIMEOUT) {
                with(ComputationalScope(this)) {
                    isWaitingRoomJoinable(
                        registrationStage = registrationStageUseCase.get(),
                        processState = stateReader.gameSnapshot.value?.processState,
                        gameTime = timelineService.subscribeTimeline().first(),
                    )
                }
            }
        }.logFailure("Failed to resolve waiting-room join state").getOrNull() ?: false

    private companion object {
        val JOINABLE_CHECK_TIMEOUT = 2.seconds
    }
}
