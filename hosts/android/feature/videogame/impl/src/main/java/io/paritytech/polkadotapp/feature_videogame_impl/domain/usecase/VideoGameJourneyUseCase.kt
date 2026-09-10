package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.chains.multiNetwork.chain.model.ChainId
import io.paritytech.polkadotapp.common.data.memory.ComputationalCache
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.memory.useSharedFlow
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_account_api.data.repository.AccountRepository
import io.paritytech.polkadotapp.feature_account_api.data.repository.getCandidateAccount
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.VideoGamesProgressUseCase
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.GameIndex
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.PersonhoodScore
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.VideoGamesProgress
import io.paritytech.polkadotapp.feature_videogame_api.domain.state.model.firstPlayedGame
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameHistoryRepository
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.accountAttendanceHistoryFlow
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.subscribeGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.GameAttendance
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.GamesHistory
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameJourneyItem
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.VideoGameJourneyItem.Status
import io.paritytech.polkadotapp.feature_videogame_impl.domain.models.earliestAttendedGame
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface VideoGameJourneyUseCase {
    context(scope: ComputationalScope)
    operator fun invoke(): Flow<List<VideoGameJourneyItem>>
}

class RealVideoGameJourneyUseCase @Inject constructor(
    private val computationalCache: ComputationalCache,
    private val chainRegistry: ChainRegistry,
    private val accountRepository: AccountRepository,
    private val gamesProgressUseCase: VideoGamesProgressUseCase,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val videoGameHistoryRepository: VideoGameHistoryRepository
) : VideoGameJourneyUseCase {
    companion object {
        private const val JOURNEY_CACHE_KEY = "VideoGameHomeInteractor.Journey"
    }

    context(scope: ComputationalScope)
    override operator fun invoke(): Flow<List<VideoGameJourneyItem>> {
        return computationalCache.useSharedFlow(JOURNEY_CACHE_KEY) {
            val chain = chainRegistry.peopleChain()
            val accountId = accountRepository.getCandidateAccount().accountIdIn(chain)

            combine(
                subscribePastGames(chain.id)
                    .logFailure("Failed to get past games"),
                gamesProgressUseCase.videoGamesProgressFlow(),
                videoGameHistoryRepository.accountAttendanceHistoryFlow(chain.id, accountId)
                    .logFailure("Failed to get account attendance history")
            ) { pastGamesResult, gameProgress, attendanceHistoryResult ->
                val pastGames = pastGamesResult.getOrNull() ?: return@combine emptyList()
                val attendanceHistory =
                    attendanceHistoryResult.getOrNull() ?: return@combine emptyList()

                constructGameJourney(gameProgress, pastGames, attendanceHistory)
            }.distinctUntilChanged()
        }
    }

    context(scope: ComputationalScope)
    private fun subscribePastGames(chainId: ChainId): Flow<Result<GamesHistory>> {
        return videoGameRepository.subscribeGameInfo(chainId).map { activeGameInfo ->
            videoGameHistoryRepository.getHistoricalGameInfos(chainId).map {
                GamesHistory(gamesHistory = it, activeGamePresent = activeGameInfo != null)
            }
        }
    }

    private fun constructGameJourney(
        gameProgress: VideoGamesProgress,
        gamesHistory: GamesHistory,
        attendance: GameAttendance
    ): List<VideoGameJourneyItem> {
        return constructPastGameJourney(gameProgress, gamesHistory, attendance) +
            constructFutureJourney(gameProgress, gamesHistory)
    }

    private fun constructPastGameJourney(
        gameProgress: VideoGamesProgress,
        gamesHistory: GamesHistory,
        attendance: GameAttendance
    ): List<VideoGameJourneyItem> {
        val earliestAttendedGame = determineEarliestAttendedGame(gameProgress, attendance) ?: return emptyList()
        val pastGames = gamesHistory.pastGamesAfterInclusive(earliestAttendedGame)

        return pastGames.map { pastGame ->
            val status = if (pastGame.gameIndex in attendance) {
                Status.SUCCESSFUL
            } else {
                Status.FAILED
            }

            VideoGameJourneyItem(
                gameIndex = pastGame.gameIndex,
                status = status,
                timestamp = pastGame.gameTimestamp
            )
        }
    }

    private fun determineEarliestAttendedGame(gameProgress: VideoGamesProgress, attendance: GameAttendance): GameIndex? {
        val candidates = listOfNotNull(
            gameProgress.firstPlayedGame(),
            attendance.earliestAttendedGame()
        )

        return candidates.minOrNull()
    }

    private fun constructFutureJourney(
        gameProgress: VideoGamesProgress,
        gamesHistory: GamesHistory,
    ): List<VideoGameJourneyItem> {
        val currentGameIndex = gamesHistory.currentGameIndex()
        val currentGameTimestamp = gamesHistory.activeGame()?.gameTimestamp

        val score: PersonhoodScore
        val pendingGameResults: Boolean

        when (gameProgress) {
            is VideoGamesProgress.PlayingGames -> {
                score = gameProgress.score
                pendingGameResults = gameProgress.pendingGameResults
            }

            is VideoGamesProgress.NotStarted -> {
                score = gameProgress.score
                pendingGameResults = false
            }

            // when processing the final game prior to obtaining the personhood,
            // show the 'pending' game widget as well
            is VideoGamesProgress.FinalGameProcessing -> {
                return listOf(
                    VideoGameJourneyItem(
                        gameIndex = currentGameIndex,
                        status = Status.PENDING,
                        timestamp = currentGameTimestamp
                    )
                )
            }

            else -> return emptyList()
        }

        return List(score.gamesLeft) { index ->
            if (index == 0) {
                VideoGameJourneyItem(
                    gameIndex = currentGameIndex,
                    status = if (pendingGameResults) Status.PENDING else Status.FUTURE,
                    timestamp = currentGameTimestamp
                )
            } else {
                VideoGameJourneyItem(
                    gameIndex = currentGameIndex + index,
                    status = Status.FUTURE,
                    timestamp = null
                )
            }
        }
    }
}
