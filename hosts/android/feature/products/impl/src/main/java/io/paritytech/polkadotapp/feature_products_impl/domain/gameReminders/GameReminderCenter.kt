@file:OptIn(ExperimentalTime::class)

package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import io.paritytech.polkadotapp.common.data.time.TimeProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.ExperimentalTime

/** Holds each product's game reminder, persisted, and keeps the OS alarm in step with it. */
interface GameReminderCenter {
    val reminders: StateFlow<List<GameReminder>>

    /** Holds [startsAtMs] as the product's reminder, replacing any it holds. */
    suspend fun schedule(productId: String, startsAtMs: Long)

    /** Drops the product's reminder. Dropping none succeeds. */
    suspend fun cancel(productId: String)

    /** Records that the player is in the product after its start. */
    suspend fun markOpened(productId: String)

    /** The player left the product; drops a reminder already opened after its start. */
    suspend fun productLeft(productId: String)

    /** Drops reminders an hour past their start and re-arms the alarms still ahead. */
    suspend fun restoreAll()
}

@Singleton
class RealGameReminderCenter @Inject constructor(
    private val store: GameReminderStore,
    private val alarms: GameReminderAlarms,
    private val timeProvider: TimeProvider,
) : GameReminderCenter {
    // One lock over every operation, so two schedules for one product never leave an alarm the store no longer knows.
    private val mutex = Mutex()
    private val state = MutableStateFlow(store.load().values.toList())

    override val reminders: StateFlow<List<GameReminder>> = state.asStateFlow()

    override suspend fun schedule(productId: String, startsAtMs: Long) = mutex.withLock {
        alarms.disarm(productId)
        armIfAhead(productId, startsAtMs)
        val reminders = store.load().toMutableMap()
        reminders[productId] = GameReminder(productId = productId, startsAtMs = startsAtMs, openedAfterStart = false)
        commit(reminders)
    }

    override suspend fun cancel(productId: String) = mutex.withLock {
        val reminders = store.load().toMutableMap()
        if (reminders.remove(productId) == null) return@withLock
        alarms.disarm(productId)
        commit(reminders)
    }

    override suspend fun markOpened(productId: String) = mutex.withLock {
        val reminders = store.load().toMutableMap()
        val reminder = reminders[productId] ?: return@withLock
        if (reminder.openedAfterStart || GameReminderPhase.of(reminder, nowMs()) != GameReminderPhase.STARTED) {
            return@withLock
        }
        reminders[productId] = reminder.copy(openedAfterStart = true)
        commit(reminders)
    }

    override suspend fun productLeft(productId: String) = mutex.withLock {
        val reminders = store.load().toMutableMap()
        val reminder = reminders[productId] ?: return@withLock
        if (!reminder.openedAfterStart) return@withLock
        reminders.remove(productId)
        alarms.disarm(productId)
        commit(reminders)
    }

    override suspend fun restoreAll() = mutex.withLock {
        val now = nowMs()
        val (expired, kept) = store.load().values.partition { GameReminderPhase.of(it, now) == GameReminderPhase.EXPIRED }
        expired.forEach { alarms.disarm(it.productId) }
        kept.forEach { armIfAhead(it.productId, it.startsAtMs) }
        commit(kept.associateBy { it.productId })
    }

    private fun armIfAhead(productId: String, startsAtMs: Long) {
        val fireAtMs = startsAtMs - GameReminderTiming.ALARM_LEAD_MS
        if (fireAtMs > nowMs()) alarms.arm(productId, fireAtMs)
    }

    private fun commit(reminders: Map<String, GameReminder>) {
        store.save(reminders)
        state.value = reminders.values.toList()
    }

    private fun nowMs(): Long = timeProvider.now().toEpochMilliseconds()
}
