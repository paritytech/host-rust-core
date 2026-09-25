@file:OptIn(ExperimentalTime::class, ExperimentalCoroutinesApi::class)

package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.data.time.TimeProvider
import io.paritytech.polkadotapp.common.presentation.AppInitializer
import io.paritytech.polkadotapp.common.utils.CoroutineDispatchers
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_products_api.presentation.SpaBrowserPayload
import io.paritytech.polkadotapp.feature_products_impl.presentation.productBotManagement.ProductsRouter
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.merge
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.ExperimentalTime

/** Opens a product's SPA when its game starts, once, and keeps the reminder in step with whether the player is in it. */
@Singleton
class GameReminderOpener @Inject constructor(
    private val center: GameReminderCenter,
    private val visibilityTracker: ProductVisibilityTracker,
    private val timeProvider: TimeProvider,
    private val productsRouter: ProductsRouter,
    private val dispatchers: CoroutineDispatchers,
) : AppInitializer {
    private sealed interface Event {
        data class Reminders(val reminders: List<GameReminder>) : Event
        data class Visibility(val visibleProductId: String?, val isForeground: Boolean) : Event
        data object Boundary : Event
    }

    context(scope: ComputationalScope)
    override fun initialize(): Result<Unit> = runCancellableCatching {
        val logic = GameReminderOpenerLogic()

        merge(
            center.reminders.map(Event::Reminders),
            combine(visibilityTracker.visibleProductId, visibilityTracker.isForeground, Event::Visibility)
                .distinctUntilChanged(),
            center.reminders.flatMapLatest { gameReminderBoundaries(it, ::nowMs) }.map { Event.Boundary },
        )
            .onEach { event ->
                val actions = when (event) {
                    is Event.Reminders -> logic.handleReminders(event.reminders, nowMs())
                    is Event.Visibility -> logic.handleVisibility(event.visibleProductId, event.isForeground, nowMs())
                    Event.Boundary -> logic.evaluate(nowMs())
                }
                actions.forEach { perform(it) }
            }
            .launchIn(scope)
    }

    private suspend fun perform(action: GameReminderOpenerAction) {
        when (action) {
            is GameReminderOpenerAction.Open -> withContext(dispatchers.main) {
                productsRouter.openSpaBrowser(SpaBrowserPayload.ByProductId(action.productId))
            }
            is GameReminderOpenerAction.MarkOpened -> center.markOpened(action.productId)
            is GameReminderOpenerAction.Left -> center.productLeft(action.productId)
        }
    }

    private fun nowMs(): Long = timeProvider.now().toEpochMilliseconds()
}
