package io.paritytech.polkadotapp.feature_videogame_impl.presentation.notifications

import dagger.hilt.android.lifecycle.HiltViewModel
import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class VideoGameNotificationsViewModel @Inject constructor(
    private val videoGameNotificationsMixin: VideoGameNotificationsMixin,
    private val videoGameRouter: VideoGameRouter,
) : BaseViewModel(), VideoGameNotificationsContract {
    override fun resolvePermissionRequest(permissionGranted: Boolean) {
        if (permissionGranted) {
            scheduleRemindersAndBack()
        }
    }

    override fun back() {
        videoGameRouter.back()
    }

    private fun scheduleRemindersAndBack() {
        launch {
            videoGameNotificationsMixin.scheduleGameReminders()
            back()
        }
    }
}
