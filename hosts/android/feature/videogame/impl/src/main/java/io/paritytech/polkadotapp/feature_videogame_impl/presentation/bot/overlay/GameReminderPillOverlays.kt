package io.paritytech.polkadotapp.feature_videogame_impl.presentation.bot.overlay

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import io.paritytech.polkadotapp.common.utils.rememberCurrentTimeMillisWithDelay
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.ChatOverlay
import io.paritytech.polkadotapp.feature_chats_api.domain.middleware.bot.CustomChatOverlayRenderer
import io.paritytech.polkadotapp.feature_products_api.domain.gameReminders.GameReminderPill
import io.paritytech.polkadotapp.feature_products_api.domain.gameReminders.GameReminderPills
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import kotlin.time.Duration.Companion.seconds
import io.paritytech.polkadotapp.common.R as RCommon

/** The product games' "Game starts in" pills, drawn with the built-in game's pill, one overlay per product. */
class GameReminderPillOverlays @Inject constructor(
    private val pills: GameReminderPills,
) {
    val overlays: Flow<List<ChatOverlay>> = pills.pills.map { shown ->
        shown.map { pill ->
            ChatOverlay(renderer = GameReminderPillRenderer(pill, pills), ownedFragmentClasses = emptySet())
        }
    }
}

private data class GameReminderPillRenderer(
    private val pill: GameReminderPill,
    private val pills: GameReminderPills,
) : CustomChatOverlayRenderer {
    @Composable
    override fun DrawOverlay() {
        val nowMs by rememberCurrentTimeMillisWithDelay(1.seconds)
        GamePillBar(
            state = VideoGamePillState.Shown.WaitingCountdown(secondsUntil(pill.startsAtMs, nowMs)),
            showChevron = true,
            onClick = { pills.open(pill.productId) },
            labelRes = RCommon.string.game_reminder_pill_label,
        )
    }
}

internal fun secondsUntil(startsAtMs: Long, nowMs: Long): Long =
    ((startsAtMs - nowMs).coerceAtLeast(0) + MILLIS_PER_SECOND - 1) / MILLIS_PER_SECOND

private const val MILLIS_PER_SECOND = 1_000L
