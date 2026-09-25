package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

sealed interface GameReminderOpenerAction {
    data class Open(val productId: String) : GameReminderOpenerAction

    data class MarkOpened(val productId: String) : GameReminderOpenerAction

    data class Left(val productId: String) : GameReminderOpenerAction
}

/**
 * Decides when a started game opens its product: once, while the app is in the foreground and the product is not
 * already on screen. Being in the product after the start marks the reminder opened; leaving it afterwards drops it.
 * Not thread-safe: feed it from one coroutine.
 */
class GameReminderOpenerLogic {
    private var current: List<GameReminder> = emptyList()
    private val requested = mutableSetOf<String>()

    // Kept until the center's next change drops the reminder, so an evaluation cannot reopen a product just left.
    private val markedOpened = mutableSetOf<String>()

    // A reschedule (same product, new start) must forget the previous start's requested/opened membership.
    private var observedStart: Map<String, Long> = emptyMap()

    private var visibleProductId: String? = null
    private var isForeground = true

    fun handleReminders(reminders: List<GameReminder>, nowMs: Long): List<GameReminderOpenerAction> {
        current = reminders
        reminders
            .filter { observedStart[it.productId] != it.startsAtMs }
            .forEach {
                requested.remove(it.productId)
                markedOpened.remove(it.productId)
            }
        observedStart = reminders.associate { it.productId to it.startsAtMs }
        requested.retainAll(observedStart.keys)
        markedOpened.retainAll(observedStart.keys)
        return evaluate(nowMs)
    }

    fun handleVisibility(visibleProductId: String?, isForeground: Boolean, nowMs: Long): List<GameReminderOpenerAction> {
        val previous = this.visibleProductId
        this.visibleProductId = visibleProductId
        this.isForeground = isForeground

        val left = previous
            ?.takeIf { it != visibleProductId && isOpenedAfterStart(it) }
            ?.let(GameReminderOpenerAction::Left)
        return listOfNotNull(left) + evaluate(nowMs)
    }

    fun evaluate(nowMs: Long): List<GameReminderOpenerAction> = current.mapNotNull { reminder ->
        val productId = reminder.productId
        when {
            GameReminderPhase.of(reminder, nowMs) != GameReminderPhase.STARTED -> null
            isOpenedAfterStart(productId) -> null
            visibleProductId == productId -> {
                markedOpened += productId
                GameReminderOpenerAction.MarkOpened(productId)
            }
            isForeground && productId !in requested -> {
                requested += productId
                GameReminderOpenerAction.Open(productId)
            }
            else -> null
        }
    }

    private fun isOpenedAfterStart(productId: String): Boolean =
        productId in markedOpened || current.any { it.productId == productId && it.openedAfterStart }
}
