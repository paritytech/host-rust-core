package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import androidx.core.app.NotificationManagerCompat
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.utils.canScheduleExactAlarms
import timber.log.Timber
import javax.inject.Inject

class RealGameReminderAlarms @Inject constructor(
    @param:ApplicationContext private val appContext: Context,
    private val notificationPublisher: GameReminderNotificationPublisher,
) : GameReminderAlarms {
    private val alarmManager = appContext.getSystemService(AlarmManager::class.java)

    // Guarded by canScheduleExactAlarms; the inexact fallback needs no permission.
    @SuppressLint("MissingPermission")
    override fun arm(productId: String, fireAtMs: Long) {
        // The reminder is still held: the opener and pill work without the OS reaching the user.
        if (!NotificationManagerCompat.from(appContext).areNotificationsEnabled()) {
            Timber.w("Game reminder for %s not armed: notifications are disabled", productId)
            return
        }

        val exact = appContext.canScheduleExactAlarms()
        val pendingIntent = pendingIntent(productId, exact)
        alarmManager.cancel(pendingIntent)
        if (exact) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMs, pendingIntent)
        } else {
            alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtMs, pendingIntent)
        }
    }

    override fun disarm(productId: String) {
        alarmManager.cancel(pendingIntent(productId, exact = false))
        notificationPublisher.cancel(productId)
    }

    // Extras do not take part in PendingIntent matching, so the same request code finds the alarm either way.
    private fun pendingIntent(productId: String, exact: Boolean): PendingIntent {
        val intent = Intent(appContext, GameReminderBroadcastReceiver::class.java).apply {
            action = GameReminderBroadcastReceiver.ACTION_GAME_REMINDER
            putExtra(GameReminderBroadcastReceiver.EXTRA_PRODUCT_ID, productId)
            putExtra(GameReminderBroadcastReceiver.EXTRA_EXACT, exact)
        }

        return PendingIntent.getBroadcast(
            appContext,
            gameReminderRequestCode(productId),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
