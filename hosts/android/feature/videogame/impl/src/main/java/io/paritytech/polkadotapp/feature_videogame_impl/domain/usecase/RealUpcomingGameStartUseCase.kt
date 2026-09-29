package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.common.utils.currentTimestampFlow
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.feature_videogame_api.domain.models.UpcomingGameStart
import io.paritytech.polkadotapp.feature_videogame_api.domain.usecase.UpcomingGameStartUseCase
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.VideoGameState
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.domain.mappers.getActualStartMillis
import io.paritytech.polkadotapp.feature_videogame_impl.domain.mappers.timeLeftUntilRegistration
import io.paritytech.polkadotapp.feature_videogame_impl.domain.mappers.timeLeftUntilStart
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

class RealUpcomingGameStartUseCase @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val gameInfoSyncService: VideoGameInfoSyncService,
) : UpcomingGameStartUseCase {
    context(scope: ComputationalScope)
    override fun subscribe(): Flow<UpcomingGameStart?> = flowOfAll {
        val chain = chainRegistry.peopleChain()
        val gamePhaseDurations = videoGameRepository.getGamePhaseDurations(chain.id)
            .logFailure("Failed to get phase durations for upcoming game start")
            .getOrElse {
                return@flowOfAll flowOf(null)
            }

        combine(
            gameInfoSyncService.subscribeCurrentActiveGameInfo(),
            currentTimestampFlow(),
            videoGameRepository.subscribeGamesSchedule(chain.id),
        ) { currentGameInfo, currentTime, schedule ->
            if (currentGameInfo != null && currentGameInfo.shouldShowCountdownForCurrentGame()) {
                UpcomingGameStart.Current(
                    timeLeftUntilStart = currentGameInfo.timeLeftUntilStart(currentTime),
                    startsAt = currentGameInfo.gameStartMillis,
                )
            } else {
                schedule.firstOrNull()?.let { closestGame ->
                    UpcomingGameStart.Next(
                        timeLeftUntilRegistrationOpens = closestGame.timeLeftUntilRegistration(
                            currentTime,
                            gamePhaseDurations
                        ),
                        timeLeftUntilStart = closestGame.timeLeftUntilStart(currentTime),
                        startsAt = closestGame.getActualStartMillis()
                    )
                }
            }
        }
    }.distinctUntilChanged()

    private fun VideoGameInfo.shouldShowCountdownForCurrentGame() = when (state) {
        is VideoGameState.Registration,
        is VideoGameState.Shuffle,
        is VideoGameState.InProgress -> true

        else -> false
    }

    // TODO: rework this calculation when repository will be returning domain models
    private fun VideoGameInfo.timeLeftUntilStart(currentTime: Timestamp) =
        (gameStartMillis - currentTime).milliseconds.coerceAtLeast(Duration.ZERO)
}
