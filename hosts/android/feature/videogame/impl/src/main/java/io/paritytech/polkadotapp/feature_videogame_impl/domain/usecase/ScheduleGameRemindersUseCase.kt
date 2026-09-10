package io.paritytech.polkadotapp.feature_videogame_impl.domain.usecase

import io.paritytech.polkadotapp.chains.multiNetwork.ChainRegistry
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.flowOfAll
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGamePhaseDurations
import io.paritytech.polkadotapp.feature_videogame_impl.data.models.onchain.OnChainVideoGameSchedule
import io.paritytech.polkadotapp.feature_videogame_impl.data.repositories.VideoGameRepositoryInternal
import io.paritytech.polkadotapp.feature_videogame_impl.domain.mappers.registrationStartsAtMillis
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.VideoGameReminderScheduler
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject

interface ScheduleGameRemindersUseCase {
    context(scope: ComputationalScope)
    fun subscribeReminderUpdates(): Flow<Unit>
}

class RealScheduleGameRemindersUseCase @Inject constructor(
    private val chainRegistry: ChainRegistry,
    private val videoGameRepository: VideoGameRepositoryInternal,
    private val videoGameReminderScheduler: VideoGameReminderScheduler
) : ScheduleGameRemindersUseCase {
    context(scope: ComputationalScope)
    override fun subscribeReminderUpdates(): Flow<Unit> = flowOfAll {
        val chain = chainRegistry.peopleChain()
        val gamePhaseDurations = videoGameRepository.getGamePhaseDurations(chain.id).getOrThrow()

        videoGameRepository.subscribeGamesSchedule(chain.id)
            .map { schedule ->
                scheduleRemindersInternal(schedule, gamePhaseDurations)
            }
    }

    private fun scheduleRemindersInternal(
        schedule: List<OnChainVideoGameSchedule>,
        gamePhaseDurations: OnChainVideoGamePhaseDurations
    ) {
        for (scheduledGame in schedule) {
            videoGameReminderScheduler.scheduleRegistration(
                scheduledGame.registrationStartsAtMillis(gamePhaseDurations)
            )
        }
    }
}
