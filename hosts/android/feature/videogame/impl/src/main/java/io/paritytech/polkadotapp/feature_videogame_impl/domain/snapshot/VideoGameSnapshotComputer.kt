package io.paritytech.polkadotapp.feature_videogame_impl.domain.snapshot

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppInitializer
import io.paritytech.polkadotapp.common.utils.FeatureOption
import io.paritytech.polkadotapp.common.utils.combineToPair
import io.paritytech.polkadotapp.common.utils.isDisabled
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.domain.VideoGameLogicStateCalculator
import io.paritytech.polkadotapp.feature_videogame_impl.domain.timeline.VideoGameTimelineService
import io.paritytech.polkadotapp.feature_videogame_impl.service.VideoGameSnapshotWriter
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import timber.log.Timber
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class VideoGameSnapshotComputer @Inject constructor(
    private val gameInfoSyncService: VideoGameInfoSyncService,
    private val timelineService: VideoGameTimelineService,
    private val stateCalculator: VideoGameLogicStateCalculator,
    private val snapshotWriter: VideoGameSnapshotWriter,
) : AppInitializer {
    context(scope: ComputationalScope)
    override fun initialize(): Result<Unit> = runCancellableCatching {
        if (FeatureOption.PERSONHOOD.isDisabled) return@runCancellableCatching

        combineToPair(
            gameInfoSyncService.subscribeCurrentActiveGameInfo(),
            timelineService.subscribeTimeline(),
        )
            .map { (info, time) ->
                if (info == null || time == null) null
                else stateCalculator.calculate(time, info)
            }
            .distinctUntilChanged()
            .onEach { snapshot ->
                if (snapshot == null) {
                    Timber.i("[VideoGame] snapshot cleared — no active game")
                } else {
                    Timber.i("[VideoGame] snapshot: game=${snapshot.gameIndex.value} state=${snapshot.processState::class.simpleName}")
                }
                snapshotWriter.updateGameSnapshot(snapshot)
            }
            .launchIn(scope)
    }
}
