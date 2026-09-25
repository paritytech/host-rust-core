@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.feature_products_api.domain.gameReminders.GameReminderPill
import io.paritytech.polkadotapp.feature_products_api.domain.gameReminders.GameReminderPills
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onStart
import javax.inject.Inject
import kotlin.time.ExperimentalTime

class RealGameReminderPills @Inject constructor(
    center: GameReminderCenter,
    visibilityTracker: ProductVisibilityTracker,
    private val timeProvider: TimeProvider,
    private val productsRouter: ProductsRouter,
) : GameReminderPills {
    override val pills: Flow<List<GameReminderPill>> =
        combine(center.reminders, visibilityTracker.visibleProductId) { reminders, visible -> reminders to visible }
            .flatMapLatest { (reminders, visibleProductId) ->
                gameReminderBoundaries(reminders, ::nowMs)
                    .onStart { emit(Unit) }
                    .map { pillsOf(reminders, visibleProductId, nowMs()) }
            }
            .distinctUntilChanged()

    override fun open(productId: String) {
        productsRouter.openSpaBrowser(SpaBrowserPayload.ByProductId(productId))
    }

    private fun pillsOf(reminders: List<GameReminder>, visibleProductId: String?, nowMs: Long) = reminders
        .filter { it.productId != visibleProductId && GameReminderPhase.of(it, nowMs) == GameReminderPhase.IMMINENT }
        .sortedBy { it.startsAtMs }
        .map { GameReminderPill(productId = it.productId, startsAtMs = it.startsAtMs) }

    private fun nowMs(): Long = timeProvider.now().toEpochMilliseconds()
}
