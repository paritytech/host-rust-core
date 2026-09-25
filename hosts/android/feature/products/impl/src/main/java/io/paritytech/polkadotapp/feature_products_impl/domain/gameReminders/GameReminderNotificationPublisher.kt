package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import android.app.Notification
import android.content.Context
import android.media.RingtoneManager
import androidx.core.app.NotificationCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.presentation.ActivityIntentProvider
import io.paritytech.polkadotapp.common.presentation.notifications.NotificationPublisher
import io.paritytech.polkadotapp.common.presentation.notifications.PolkadotNotificationChannel
import javax.inject.Inject
import io.paritytech.polkadotapp.common.R as RCommon

class GameReminderNotificationPublisher @Inject constructor(
    @ApplicationContext context: Context,
    intentProvider: ActivityIntentProvider,
) : NotificationPublisher(context, intentProvider) {
    /** [asAlarm] rings like the built-in game's start alarm; otherwise an ordinary product notification is posted. */
    fun publish(productId: String, asAlarm: Boolean) {
        val channel = if (asAlarm) PolkadotNotificationChannel.PRODUCT_GAME_ALARM else PolkadotNotificationChannel.PRODUCTS

        val builder = NotificationCompat.Builder(appContext, channel.id)
            .setupDefaultNotification(deepLink = GameReminderDeeplink.build(productId))
            .setContentTitle(appContext.getString(RCommon.string.video_game_start_reminder_title))
            .setContentText(appContext.getString(RCommon.string.video_game_start_reminder_message))

        val notification = if (asAlarm) {
            builder
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setVibrate(channel.vibrationPattern)
                .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE))
                .build()
                .apply { flags = flags or Notification.FLAG_INSISTENT }
        } else {
            builder
                .setCategory(NotificationCompat.CATEGORY_REMINDER)
                .build()
        }

        publish(gameReminderRequestCode(productId), channel, notification)
    }

    fun cancel(productId: String) {
        cancel(gameReminderRequestCode(productId))
    }
}

/**
 * One PendingIntent and one notification per product, so every schedule replaces the previous one. Namespaced so it
 * does not collide with the product's own scheduled notification ids.
 */
internal fun gameReminderRequestCode(productId: String): Int = "game:$productId".hashCode()
