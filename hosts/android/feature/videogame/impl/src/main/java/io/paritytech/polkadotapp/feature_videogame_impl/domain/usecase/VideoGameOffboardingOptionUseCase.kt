package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameOffboardingOption
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import javax.inject.Inject

interface VideoGameOffboardingOptionUseCase {
    context(scope: ComputationalScope)
    fun subscribe(): Flow<VideoGameOffboardingOption>
}

class RealVideoGameOffboardingOptionUseCase @Inject constructor(
    private val videoGameRegistrationStageUseCase: VideoGameRegistrationStageUseCase,
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val videoGameInfoSyncService: VideoGameInfoSyncService
) : VideoGameOffboardingOptionUseCase {
    context(scope: ComputationalScope)
    override fun subscribe(): Flow<VideoGameOffboardingOption> = combine(
        videoGameRegistrationStageUseCase.subscribe(),
        gamesProgressUseCase.videoGamesProgressFlow(),
        videoGameInfoSyncService.subscribeCurrentActiveGameInfo()
    ) { registrationStage, progress, gameInfo ->
        val gameState = gameInfo?.state

        when (progress) {
            is VideoGamesProgress.PlayingGames -> {
                val isGameNotInRegistration = gameState != null && gameState !is VideoGameState.Registration
                if (progress.hasSuspendedPersonhood || registrationStage == VideoGameRegistrationStage.Registered || isGameNotInRegistration) {
                    VideoGameOffboardingOption.UNAVAILABLE
                } else {
                    VideoGameOffboardingOption.OFFBOARD
                }
            }

            is VideoGamesProgress.Started -> {
                VideoGameOffboardingOption.OFFBOARD
            }

            is VideoGamesProgress.NotStarted -> {
                VideoGameOffboardingOption.QUIT
            }

            is VideoGamesProgress.ExternallyRecognized -> {
                error("Personhood is externally recognized, should not be in video game flow")
            }
        }
    }
}
