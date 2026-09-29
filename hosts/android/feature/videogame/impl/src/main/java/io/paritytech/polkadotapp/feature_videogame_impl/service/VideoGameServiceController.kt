package io.paritytech.polkadotapp.feature_videogame_impl.service

import android.content.Context
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber
import javax.inject.Inject

class VideoGameServiceController @Inject constructor(
    @param:ApplicationContext private val context: Context
) {
    fun start() {
        Timber.i("[VideoGame] Service start requested")
        context.startForegroundService(VideoGameService.startGameIntent(context))
    }

    fun stop() {
        Timber.i("[VideoGame] Service stop requested")
        context.startService(VideoGameService.stopGameIntent(context))
    }
}
