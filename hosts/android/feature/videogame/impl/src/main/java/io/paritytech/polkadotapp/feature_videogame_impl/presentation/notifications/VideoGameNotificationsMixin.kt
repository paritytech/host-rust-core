package io.paritytech.polkadotapp.feature_videogame_impl.presentation.notifications

import android.Manifest.permission.POST_NOTIFICATIONS
import android.content.Context
import android.os.Build
import dagger.hilt.android.qualifiers.ApplicationContext
import io.paritytech.polkadotapp.common.data.memory.ComputationalScope
import io.paritytech.polkadotapp.common.utils.canScheduleExactAlarms
import io.paritytech.polkadotapp.common.utils.permissions.PermissionAsker
import io.paritytech.polkadotapp.common.utils.permissions.isPermissionGranted
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.getCurrentActiveGameInfo
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.VideoGameReminderScheduler
import javax.inject.Inject

class VideoGameNotificationsMixin @Inject constructor(
    @ApplicationContext val context: Context,
    private val permissionAsker: PermissionAsker,
    private val gameInfoSyncService: VideoGameInfoSyncService,
    private val videoGameReminderScheduler: VideoGameReminderScheduler,
    private val router: VideoGameRouter
) {
    context(scope: ComputationalScope)
    suspend fun checkPermissionsAndScheduleGameReminders() {
        if (context.checkIfPermissionsGranted()) {
            scheduleGameReminders()
        } else {
            router.openVideoGameNotifications()
        }
    }

    context(scope: ComputationalScope)
    suspend fun scheduleGameReminders() {
        val gameInfo = gameInfoSyncService.getCurrentActiveGameInfo()

        videoGameReminderScheduler.scheduleWaitingRoom(gameInfo.gameStartMillis)
        videoGameReminderScheduler.scheduleGameAboutToStart(gameInfo.gameStartMillis)
        videoGameReminderScheduler.scheduleGameStart(gameInfo.gameStartMillis)
    }

    private fun Context.checkIfPermissionsGranted(): Boolean {
        val hasNotificationsPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissionAsker.isPermissionGranted(POST_NOTIFICATIONS)
        } else {
            true
        }

        val alarmsAllowed = canScheduleExactAlarms()

        return hasNotificationsPermission && alarmsAllowed
    }
}
