package io.paritytech.polkadotapp.feature_videogame_impl.domain.timeline

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.currentTimestampFlow
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

interface VideoGameTimelineService {
    context(scope: ComputationalScope)
    fun subscribeTimeline(): Flow<Duration?>
}

class RealVideoGameTimelineService @Inject constructor(
    private val gameInfoSyncService: VideoGameInfoSyncService
) : VideoGameTimelineService {
    context(scope: ComputationalScope)
    override fun subscribeTimeline(): Flow<Duration?> = gameInfoSyncService.subscribeCurrentActiveGameInfo()
        .flatMapLatest { gameInfo ->
            if (gameInfo == null) {
                flowOf<Duration?>(null)
            } else {
                currentTimestampFlow()
                    .map { currentTime ->
                        (currentTime - gameInfo.gameStartMillis).milliseconds
                    }
            }
        }.distinctUntilChanged()
}

context(scope: ComputationalScope)
fun VideoGameTimelineService.currentActiveGameTimeline() = subscribeTimeline().filterNotNull()
