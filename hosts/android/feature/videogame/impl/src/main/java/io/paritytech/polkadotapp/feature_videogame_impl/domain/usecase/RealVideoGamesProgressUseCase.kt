package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalCache
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.memory.useSharedFlow
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.BandersnatchSecretsStorage
import io.paritytech.polkadotapp.feature_account_api.data.storage.accountSecrets.getAliasInContext
import io.paritytech.polkadotapp.feature_people_api.domain.useCase.PersonStatusUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_impl.data.ScoreContextProvider
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainArchivedPlayer
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainParticipant
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePlayerInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameRecognition
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.calculatePersonhoodScore
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.firstGame
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.isRecognizedViaGames
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.ScoreRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeAccountArchivedPlayer
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeOurParticipant
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeOurPlayer
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import javax.inject.Inject

internal class RealVideoGamesProgressUseCase @Inject constructor(
    private val scoreRepository: ScoreRepository,
    private val gameRepository: VideoGameRepositoryInternal,
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val computationalCache: ComputationalCache,
    private val personStatusUseCase: PersonStatusUseCase,
    private val bandersnatchSecretsStorage: BandersnatchSecretsStorage,
    private val scoreContextProvider: ScoreContextProvider
) : VideoGamesProgressUseCase {
    companion object {
        const val GAME_PROGRESS_CACHE_KEY = "RealVideoGamesProgressUseCase.GameProgress"
    }

    context(scope: ComputationalScope)
    override fun videoGamesProgressFlow(): Flow<VideoGamesProgress> {
        return computationalCache.useSharedFlow(GAME_PROGRESS_CACHE_KEY) {
            videoGamesProgressFlowInternal()
        }
    }

    context(scope: ComputationalScope)
    override suspend fun videoGameProgress(): VideoGamesProgress {
        return videoGamesProgressFlow().first()
    }

    private suspend fun videoGamesProgressFlowInternal(): Flow<VideoGamesProgress> {
        val chain = chainRegistry.peopleChain()
        val candidateAccount = accountRepository.getCandidateAccount()
        val playerAccountId = candidateAccount.accountIdIn(chain)

        val scoreAlias = bandersnatchSecretsStorage.getAliasInContext(candidateAccount.id, scoreContextProvider.context())

        return combine(
            scoreRepository.subscribeOurParticipant(chain.id, playerAccountId, scoreAlias),
            gameRepository.subscribeOurPlayer(chain.id, playerAccountId, scoreAlias),
            gameRepository.subscribeAccountArchivedPlayer(chain.id, playerAccountId),
            personStatusUseCase.personhoodAccountsFullySetFlow(),
            scoreRepository.subscribePersonhoodThreshold(chain.id)
        ) { scoreParticipant, gamePlayer, archivedPlayer, isAlreadyPerson, personhoodThreshold ->
            createVideoGamesProgress(scoreParticipant, gamePlayer?.data, archivedPlayer, personhoodThreshold, isAlreadyPerson)
        }
    }

    private fun createVideoGamesProgress(
        scoreParticipant: OnChainParticipant?,
        gamePlayer: OnChainVideoGamePlayerInfo?,
        archivedPlayer: OnChainArchivedPlayer?,
        personhoodThreshold: Int,
        isAlreadyPerson: Boolean
    ): VideoGamesProgress {
        val personhoodScore = scoreParticipant.calculatePersonhoodScore(personhoodThreshold)
        val pendingGameResults = pendingGameResults(gamePlayer)
        val firstPlayedGame = gamePlayer?.firstGame ?: archivedPlayer?.firstGame

        return when {
            scoreParticipant == null -> VideoGamesProgress.NotStarted(isAlreadyPerson, personhoodScore)

            scoreParticipant.recognition is OnChainVideoGameRecognition.ExternallyRecognized -> VideoGamesProgress.ExternallyRecognized

            scoreParticipant.recognition.isRecognizedViaGames() -> VideoGamesProgress.PersonhoodReached(
                firstPlayedGame = firstPlayedGame
            )

            personhoodScore.gamesLeft == 0 -> VideoGamesProgress.ReadyToReachPersonhood(
                firstPlayedGame = firstPlayedGame,
            )

            personhoodScore.gamesLeft == 1 && pendingGameResults -> VideoGamesProgress.FinalGameProcessing(
                firstPlayedGame = firstPlayedGame,
                hasSuspendedPersonhood = scoreParticipant.hasEverReachedPersonhood
            )

            else -> VideoGamesProgress.PlayingGames(
                firstPlayedGame = gamePlayer?.firstGame ?: archivedPlayer?.firstGame,
                score = personhoodScore,
                pendingGameResults = pendingGameResults,
                hasSuspendedPersonhood = scoreParticipant.hasEverReachedPersonhood
            )
        }
    }

    private fun pendingGameResults(gamePlayer: OnChainVideoGamePlayerInfo?): Boolean {
        return gamePlayer != null && gamePlayer.sentReport
    }
}
