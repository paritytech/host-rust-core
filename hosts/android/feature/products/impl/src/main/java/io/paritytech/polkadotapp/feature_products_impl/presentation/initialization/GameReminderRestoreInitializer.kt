package io.paritytech.polkadotapp.feature_products_impl.presentation.initialization

import io.paritytech.polkadotapp.common.data.app.AppLifecycleState
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.presentation.AppInitializer
import io.paritytech.polkadotapp.common.presentation.AppLifecycleObserver
import io.paritytech.polkadotapp.common.utils.logFailure
import io.paritytech.polkadotapp.common.utils.runCancellableCatching
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderCenter
import io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders.GameReminderNotificationPublisher
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import javax.inject.Inject

class GameReminderRestoreInitializer @Inject constructor(
    private val center: GameReminderCenter,
    private val notificationPublisher: GameReminderNotificationPublisher,
    private val appLifecycleObserver: AppLifecycleObserver,
) : AppInitializer {
    context(scope: ComputationalScope)
    override fun initialize(): Result<Unit> {
        scope.launch {
            runCancellableCatching { center.restoreAll() }
                .logFailure("Failed to restore game reminders")
        }

        // An alarm-style notification rings until it is touched; coming back to the app answers it.
        appLifecycleObserver.subscribe()
            .filter { it == AppLifecycleState.FOREGROUND }
            .onEach { center.reminders.value.forEach { notificationPublisher.cancel(it.productId) } }
            .launchIn(scope)

        return Result.success(Unit)
    }
}
