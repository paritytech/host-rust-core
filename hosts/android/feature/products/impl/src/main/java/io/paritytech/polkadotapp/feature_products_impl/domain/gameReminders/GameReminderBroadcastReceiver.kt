package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import io.paritytech.polkadotapp.common.utils.launchAsyncJob
import kotlinx.coroutines.flow.first
import javax.inject.Inject

@AndroidEntryPoint
class GameReminderBroadcastReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_GAME_REMINDER =
            "io.paritytech.polkadotapp.feature_products.domain.gameReminders.GAME_REMINDER"
        const val EXTRA_PRODUCT_ID = "product_id"
        const val EXTRA_EXACT = "exact"
    }

    @Inject
    lateinit var notificationPublisher: GameReminderNotificationPublisher

    @Inject
    lateinit var visibilityTracker: ProductVisibilityTracker

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_GAME_REMINDER) return

        val productId = intent.getStringExtra(EXTRA_PRODUCT_ID) ?: return
        val exact = intent.getBooleanExtra(EXTRA_EXACT, false)

        launchAsyncJob {
            // The player is already in the product: ringing would only interrupt the game they are waiting for.
            if (visibilityTracker.visibleProductId.first() == productId) return@launchAsyncJob

            notificationPublisher.publish(productId, asAlarm = exact)
        }
    }
}
