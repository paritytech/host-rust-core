package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import kotlinx.serialization.Serializable

/** Offsets around a product's game start that the host applies; they never travel on the wire. */
object GameReminderTiming {
    const val ALARM_LEAD_MS = 20_000L
    const val PILL_LEAD_MS = 180_000L
    const val OPEN_WINDOW_MS = 3_600_000L
}

/** The one reminder a product holds. Leaving the product once [openedAfterStart] is set drops it. */
@Serializable
data class GameReminder(
    val productId: String,
    val startsAtMs: Long,
    val openedAfterStart: Boolean,
)

enum class GameReminderPhase {
    /** More than three minutes before the start. */
    PENDING,

    /** In the last three minutes before the start. */
    IMMINENT,

    /** From the start until an hour after it. */
    STARTED,

    /** An hour or more after the start. */
    EXPIRED;

    companion object {
        fun of(reminder: GameReminder, nowMs: Long): GameReminderPhase {
            val untilStart = reminder.startsAtMs - nowMs
            return when {
                untilStart > GameReminderTiming.PILL_LEAD_MS -> PENDING
                untilStart > 0 -> IMMINENT
                -untilStart < GameReminderTiming.OPEN_WINDOW_MS -> STARTED
                else -> EXPIRED
            }
        }
    }
}

/** The first instant after [nowMs] at which some reminder changes phase. */
fun nextGameReminderBoundary(nowMs: Long, reminders: Collection<GameReminder>): Long? =
    reminders
        .flatMap { reminder ->
            listOf(
                reminder.startsAtMs - GameReminderTiming.PILL_LEAD_MS,
                reminder.startsAtMs,
                reminder.startsAtMs + GameReminderTiming.OPEN_WINDOW_MS,
            )
        }
        .filter { it > nowMs }
        .minOrNull()
