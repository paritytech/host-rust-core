package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.currentTimestampFlow
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatOverlayRenderer
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameTimings
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.RealProductGameReminder
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

class ProductGamePillOverlayRenderer : CustomChatOverlayRenderer {
    @Composable
    override fun DrawOverlay() {
        val vm: ProductGamePillOverlayViewModel = hiltViewModel()
        val state by vm.pillState.collectAsStateWithLifecycle()
        (state as? VideoGamePillState.Shown)?.let { shown ->
            GamePillBar(
                state = shown,
                showChevron = true,
                onClick = vm::open,
            )
        }
    }
}

@HiltViewModel
@OptIn(ExperimentalCoroutinesApi::class)
internal class ProductGamePillOverlayViewModel @Inject constructor(
    private val reminder: RealProductGameReminder,
    private val router: VideoGameRouter,
) : BaseViewModel() {
    val pillState: StateFlow<VideoGamePillState> = reminder.slot
        .flatMapLatest { slot ->
            slot?.let { currentTimestampFlow().map { now -> countdown((it.startsAtMillis - now).milliseconds) } }
                ?: flowOf(VideoGamePillState.Hidden)
        }
        .stateInBackground(SharingStarted.WhileSubscribed(), VideoGamePillState.Hidden)

    fun open() {
        reminder.currentSlot()?.let { router.openGameProduct(it.productId) }
    }

    private fun countdown(untilStart: Duration): VideoGamePillState =
        if (untilStart > Duration.ZERO && untilStart <= VideoGameTimings.WAITING_ROOM_AVAILABLE_BEFORE) {
            VideoGamePillState.Shown.WaitingCountdown(untilStart.inWholeSeconds)
        } else {
            VideoGamePillState.Hidden
        }
}
