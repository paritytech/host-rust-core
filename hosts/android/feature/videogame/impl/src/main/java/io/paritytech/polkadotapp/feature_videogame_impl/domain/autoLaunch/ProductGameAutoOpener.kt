package io.paritytech.polkadotapp.feature_videogame_impl.domain.autoLaunch

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.common.presentation.AppInitializer
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.common.presentation.subscribeIsForeground
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.ProductGameSlot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.RealProductGameReminder
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.mapLatest
import javax.inject.Inject

@OptIn(ExperimentalCoroutinesApi::class)
class ProductGameAutoOpener @Inject constructor(
    private val reminder: RealProductGameReminder,
    private val appLifecycleObserver: AppLifecycleObserver,
    private val router: VideoGameRouter,
    private val timeProvider: TimeProvider,
) : AppInitializer {
    context(scope: ComputationalScope)
    override fun initialize(): Result<Unit> = runCancellableCatching {
        combine(reminder.slot, appLifecycleObserver.subscribeIsForeground()) { slot, foreground ->
            slot.takeIf { foreground }
        }
            .mapLatest { slot -> slot?.let { openAtStart(it) } }
            .launchIn(scope)
    }

    private suspend fun openAtStart(slot: ProductGameSlot) {
        val untilStart = slot.startsAtMillis - timeProvider.now().toEpochMilliseconds()
        if (untilStart < 0) return

        delay(untilStart)
        router.openGameProduct(slot.productId)
        reminder.clear(slot)
    }
}
