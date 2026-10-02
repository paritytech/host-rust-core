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
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.time.Duration.Companion.milliseconds

@HiltViewModel
internal class ProductGamePillOverlayViewModel @Inject constructor(
    reminder: RealProductGameReminder,
    private val router: VideoGameRouter,
) : BaseViewModel(), GamePillViewModel {
    private class Countdown(val slot: ProductGameSlot, val secondsLeft: Long)

    // The soonest start inside the countdown window, if any; slots are held soonest first.
    private val countdown: StateFlow<Countdown?> =
        combine(reminder.slots, currentTimestampFlow()) { slots, now ->
            slots.firstNotNullOfOrNull { slot -> slot.countdownAt(now) }
        }.stateInBackground(SharingStarted.WhileSubscribed(), null)

    override val pillState: StateFlow<VideoGamePillState> = countdown
        .map { it?.let { VideoGamePillState.Shown.WaitingCountdown(it.secondsLeft) } ?: VideoGamePillState.Hidden }
        .stateInBackground(SharingStarted.WhileSubscribed(), VideoGamePillState.Hidden)

    override fun onPillClicked() {
        countdown.value?.let { router.openGameProduct(it.slot.product()) }
    }

    private fun ProductGameSlot.countdownAt(nowMillis: Long): Countdown? {
        val untilStart = (startsAtMillis - nowMillis).milliseconds
        val inWindow = untilStart.isPositive() && untilStart <= VideoGameTimings.WAITING_ROOM_AVAILABLE_BEFORE
        return if (inWindow) Countdown(this, untilStart.inWholeSeconds) else null
    }
}
