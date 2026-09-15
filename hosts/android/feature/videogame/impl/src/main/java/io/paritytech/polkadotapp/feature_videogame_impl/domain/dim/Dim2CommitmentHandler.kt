package io.paritytech.polkadotapp.feature_videogame_impl.domain.dim

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.flatMap
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatBotData
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimCommitmentHandler
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimId
import io.paritytech.polkadotapp.feature_people_api.domain.dim.DimState
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameRegistrationStage
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameOffboardingOption
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameOffboardingOptionUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameRegistrationStageUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import javax.inject.Inject

class Dim2CommitmentHandler @Inject constructor(
    private val videoGameRegistrationStageUseCase: VideoGameRegistrationStageUseCase,
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val chainRegistry: ChainRegistry,
    private val offboardingOptionUseCase: VideoGameOffboardingOptionUseCase
) : DimCommitmentHandler {
    companion object {
        const val DIM_ID: DimId = "dim2"
    }

    override val dimId: DimId = DIM_ID

    override val botId: String = ChatBotData.weeklyGame().id

    context(scope: ComputationalScope)
    override fun observeState(): Flow<DimState> = combine(
        videoGameRegistrationStageUseCase.subscribe(),
        gamesProgressUseCase.videoGamesProgressFlow()
    ) { registrationStage, progress ->
        when (progress) {
            is VideoGamesProgress.PlayingGames -> {
                val isCancellable = !progress.hasSuspendedPersonhood &&
                    registrationStage != VideoGameRegistrationStage.Registered
                DimState.Started(cancellable = isCancellable)
            }
            is VideoGamesProgress.Started -> DimState.Started(cancellable = true)
            is VideoGamesProgress.NotStarted,
            VideoGamesProgress.ExternallyRecognized -> DimState.NotStarted
        }
    }

    context(scope: ComputationalScope)
    override suspend fun cancel(): Result<Unit> = runCatching {
        offboardingOptionUseCase.subscribe().first()
    }.flatMap { option ->
        when (option) {
            VideoGameOffboardingOption.QUIT -> Result.success(Unit)
            VideoGameOffboardingOption.OFFBOARD -> videoGameRepository.offboard(chainRegistry.peopleChain())
            VideoGameOffboardingOption.UNAVAILABLE -> Result.failure(IllegalStateException("Offboarding is unavailable"))
        }
    }
}
