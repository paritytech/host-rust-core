package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.currentTimestampFlow
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.ProductGameSlot
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.RealProductGameReminder
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.product
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import javax.inject.Inject
import kotlin.time.Duration.Companion.milliseconds

@HiltViewModel
internal class ProductGamePillOverlayViewModel @Inject constructor(
    reminder: RealProductGameReminder,
    private val router: VideoGameRouter,
) : BaseViewModel(), GamePillViewModel {
    // The soonest start inside the countdown window, if any.
    private val countingDown: StateFlow<ProductGameSlot?> =
        combine(reminder.slots, currentTimestampFlow()) { slots, now ->
            slots.firstOrNull { slot ->
                val untilStart = slot.startsAtMillis - now
                untilStart > 0 && untilStart <= VideoGameTimings.WAITING_ROOM_AVAILABLE_BEFORE.inWholeMilliseconds
            }
        }.stateInBackground(SharingStarted.WhileSubscribed(), null)

    override val pillState: StateFlow<VideoGamePillState> = combine(countingDown, currentTimestampFlow()) { slot, now ->
        slot?.let { VideoGamePillState.Shown.WaitingCountdown((it.startsAtMillis - now).milliseconds.inWholeSeconds) }
            ?: VideoGamePillState.Hidden
    }.stateInBackground(SharingStarted.WhileSubscribed(), VideoGamePillState.Hidden)

    override fun onPillClicked() {
        countingDown.value?.let { router.openGameProduct(it.product()) }
    }
}
