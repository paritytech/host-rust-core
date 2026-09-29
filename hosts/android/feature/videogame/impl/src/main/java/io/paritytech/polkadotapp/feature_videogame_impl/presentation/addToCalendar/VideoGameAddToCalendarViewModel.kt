package io.paritytech.polkadotapp.feature_videogame_impl.presentation.addToCalendar

import io.paritytech.polkadotapp.common.presentation.screens.BaseViewModel
import io.paritytech.polkadotapp.common.presentation.sharing.SharingManager
import io.paritytech.polkadotapp.common.utils.EventCalendarSharing
import io.paritytech.polkadotapp.common.utils.launchUnit
import io.paritytech.polkadotapp.feature_videogame_impl.VideoGameRouter
import io.paritytech.polkadotapp.feature_videogame_impl.data.VideoGameInfoSyncService
import io.paritytech.polkadotapp.feature_videogame_impl.data.getCurrentActiveGameInfo
import javax.inject.Inject

class VideoGameAddToCalendarViewModel @Inject constructor(
    private val sharingManager: SharingManager,
    private val router: VideoGameRouter,
    private val gameInfoSyncService: VideoGameInfoSyncService
) : BaseViewModel(), VideoGameAddToCalendarContract {
    override fun confirm() = launchUnit {
        sharingManager.shareCalendarEvent(
            EventCalendarSharing(
                title = "Web3Citizenship video game",
                startTime = gameInfoSyncService.getCurrentActiveGameInfo().gameStartMillis
            )
        )

        router.back()
    }

    override fun decline() {
        router.back()
    }
}
