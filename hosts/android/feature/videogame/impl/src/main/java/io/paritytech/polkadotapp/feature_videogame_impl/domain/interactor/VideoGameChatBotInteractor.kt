package io.paritytech.polkadotapp.feature_videogame_impl.domain.interactor

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_people_api.data.personSetup.PersonSetupStarter
import io.paritytech.polkadotapp.feature_videogame_api.data.updaters.VideoGameUpdateSystem
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase.VideoGameClaimCitizenshipUseCase
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import javax.inject.Inject

interface VideoGameChatBotInteractor {
    fun startUpdates(): Flow<*>

    context(scope: ComputationalScope)
    suspend fun observeGameProgressAndClaimCitizenship()

    context(scope: ComputationalScope)
    suspend fun observeGameProgressAndStartPersonSetup()
}

class RealVideoGameChatBotInteractor @Inject constructor(
    private val videoGameUpdateSystem: VideoGameUpdateSystem,
    private val personSetupStarter: PersonSetupStarter,
    private val videoGamesProgressUseCase: VideoGamesProgressUseCase,
    private val claimCitizenshipUseCase: VideoGameClaimCitizenshipUseCase,
) : VideoGameChatBotInteractor {
    context(scope: ComputationalScope)
    override suspend fun observeGameProgressAndClaimCitizenship() {
        videoGamesProgressUseCase.videoGamesProgressFlow()
            .first { it is VideoGamesProgress.ReadyToReachPersonhood }

        claimCitizenshipUseCase()
            .logFailure("Unable to claim citizenship")
    }

    context(scope: ComputationalScope)
    override suspend fun observeGameProgressAndStartPersonSetup() {
        videoGamesProgressUseCase.videoGamesProgressFlow()
            .first { it is VideoGamesProgress.PersonhoodReached }

        personSetupStarter.startPersonSetup()
    }

    override fun startUpdates(): Flow<*> {
        return videoGameUpdateSystem.updateSystem.start()
    }
}
