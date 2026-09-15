package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import io.paritytech.polkadotapp.common.domain.model.Timestamp
import io.paritytech.polkadotapp.common.presentation.resources.ContextManager
import io.paritytech.polkadotapp.feature_videogame_impl.data.notifications.VideoGameSettingsPreferences
import javax.inject.Inject
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

interface VideoGameReminderScheduler {
    fun scheduleRegistration(timestamp: Timestamp)
    fun scheduleWaitingRoom(gameStartMillis: Timestamp)
    fun scheduleGameAboutToStart(gameStartMillis: Timestamp)
    fun scheduleGameStart(gameStartMillis: Timestamp)
}

class RealVideoGameReminderScheduler @Inject constructor(
    private val contextManager: ContextManager,
    private val alarmPreferences: VideoGameSettingsPreferences
) : VideoGameReminderScheduler {
    private companion object {
        val WAITING_ROOM_SCHEDULE_OFFSET_MILLIS = 5.minutes.inWholeMilliseconds
        val ABOUT_TO_START_SCHEDULE_OFFSET_MILLIS = 1.minutes.inWholeMilliseconds
    }

    private val alarmManager = contextManager.applicationContext.getSystemService(AlarmManager::class.java)

    override fun scheduleRegistration(timestamp: Timestamp) {
        scheduleAlarm(VideoGameNotificationType.RegistrationOpened(timestamp), timestamp)
    }

    override fun scheduleWaitingRoom(gameStartMillis: Timestamp) {
        scheduleAlarm(
            VideoGameNotificationType.WaitingRoomAvailable,
            gameStartMillis - WAITING_ROOM_SCHEDULE_OFFSET_MILLIS
        )
    }

    override fun scheduleGameAboutToStart(gameStartMillis: Timestamp) {
        scheduleAlarm(
            VideoGameNotificationType.GameAboutToStart,
            gameStartMillis - ABOUT_TO_START_SCHEDULE_OFFSET_MILLIS
        )
    }

    override fun scheduleGameStart(gameStartMillis: Timestamp) {
        val offsetMillis = alarmPreferences.getAlarmOffset().seconds.seconds.inWholeMilliseconds
        val triggerAtMillis = gameStartMillis - offsetMillis

        if (triggerAtMillis <= System.currentTimeMillis()) {
            cancelAlarm(VideoGameNotificationType.GameStartsSoon)
            return
        }

        scheduleAlarm(VideoGameNotificationType.GameStartsSoon, triggerAtMillis)
    }

    private fun cancelAlarm(notificationType: VideoGameNotificationType) {
        alarmManager.cancel(createPendingIntent(notificationType))
    }

    @SuppressLint("MissingPermission")
    private fun scheduleAlarm(
        notificationType: VideoGameNotificationType,
        timestamp: Timestamp
    ) {
        val pendingIntent = createPendingIntent(notificationType)

        alarmManager.cancel(pendingIntent)

        val canScheduleAlarms = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else true

        if (canScheduleAlarms) {
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP,
                timestamp,
                pendingIntent
            )
        }
    }

    private fun createPendingIntent(
        notificationType: VideoGameNotificationType,
    ): PendingIntent {
        val intent = Intent(contextManager.applicationContext, VideoGameReminderBroadcastReceiver::class.java).apply {
            action = VideoGameReminderBroadcastReceiver.ACTION_POST_NOTIFICATION
            putExtra(VideoGameReminderBroadcastReceiver.EXTRA_NOTIFICATION_TYPE, notificationType)
        }

        return PendingIntent.getBroadcast(
            contextManager.applicationContext,
            notificationType.requestCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun VideoGameNotificationType.requestCode(): Int = when (this) {
        is VideoGameNotificationType.RegistrationOpened -> 1
        VideoGameNotificationType.WaitingRoomAvailable -> 2
        VideoGameNotificationType.GameAboutToStart -> 3
        VideoGameNotificationType.GameStartsSoon -> 4
    }
}
