package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.utils.stateInBackground
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatOverlayRenderer
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.RealProductGameReminder
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import javax.inject.Inject
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

internal val PRODUCT_GAME_PILL_LEAD = 5.minutes

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
    private val timeProvider: TimeProvider,
) : BaseViewModel() {
    val pillState: StateFlow<VideoGamePillState> = reminder.slot
        .flatMapLatest { slot -> slot?.let { countdown(it.startsAtMillis) } ?: flowOf(VideoGamePillState.Hidden) }
        .stateInBackground(SharingStarted.WhileSubscribed(), VideoGamePillState.Hidden)

    fun open() {
        reminder.currentSlot()?.let { router.openGameProduct(it.productId) }
    }

    private fun countdown(startsAtMillis: Long): Flow<VideoGamePillState> = flow {
        while (true) {
            val untilStart = (startsAtMillis - timeProvider.now().toEpochMilliseconds()).milliseconds
            if (untilStart <= Duration.ZERO) {
                emit(VideoGamePillState.Hidden)
                break
            }
            if (untilStart <= PRODUCT_GAME_PILL_LEAD) {
                emit(VideoGamePillState.Shown.WaitingCountdown(untilStart.inWholeSeconds))
                delay(1.seconds)
            } else {
                emit(VideoGamePillState.Hidden)
                // Re-check at least once a minute: a sleeping device stretches delays.
                delay((untilStart - PRODUCT_GAME_PILL_LEAD).coerceAtMost(1.minutes))
            }
        }
    }
}
