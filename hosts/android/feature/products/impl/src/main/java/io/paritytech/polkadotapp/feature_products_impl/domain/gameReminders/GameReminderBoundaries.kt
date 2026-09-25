package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow

/** Emits each time one of [reminders] changes phase, until none has a boundary left. */
fun gameReminderBoundaries(reminders: List<GameReminder>, nowMs: () -> Long): Flow<Unit> = flow {
    while (true) {
        val now = nowMs()
        val next = nextGameReminderBoundary(now, reminders) ?: break
        delay(next - now)
        emit(Unit)
    }
}
