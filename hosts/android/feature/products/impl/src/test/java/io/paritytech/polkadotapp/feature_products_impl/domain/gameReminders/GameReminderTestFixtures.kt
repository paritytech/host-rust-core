package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

internal class InMemoryGameReminderStore(initial: Collection<GameReminder> = emptyList()) : GameReminderStore {
    var saved: Map<String, GameReminder> = initial.associateBy { it.productId }
        private set

    override fun load(): Map<String, GameReminder> = saved

    override fun save(reminders: Map<String, GameReminder>) {
        saved = reminders.toMap()
    }
}

internal class RecordingGameReminderAlarms : GameReminderAlarms {
    sealed interface Call {
        data class Arm(val productId: String, val fireAtMs: Long) : Call
        data class Disarm(val productId: String) : Call
    }

    val calls = mutableListOf<Call>()

    val armed: Map<String, Long>
        get() = calls.fold(mutableMapOf()) { armed, call ->
            when (call) {
                is Call.Arm -> armed[call.productId] = call.fireAtMs
                is Call.Disarm -> armed.remove(call.productId)
            }
            armed
        }

    override fun arm(productId: String, fireAtMs: Long) {
        calls += Call.Arm(productId, fireAtMs)
    }

    override fun disarm(productId: String) {
        calls += Call.Disarm(productId)
    }
}

internal const val GAME_START_MS = 1_800_000_000_000L

internal fun gameReminder(
    productId: String = "jollity.dot",
    startsAtMs: Long = GAME_START_MS,
    openedAfterStart: Boolean = false,
) = GameReminder(productId = productId, startsAtMs = startsAtMs, openedAfterStart = openedAfterStart)
