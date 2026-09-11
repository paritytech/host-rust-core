package io.paritytech.polkadotapp.feature_videogame_impl.data.notifications

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.GameStartAlarmOffset
import javax.inject.Inject
import javax.inject.Singleton

private const val KEY_ALARM_OFFSET_SECONDS = "video_game_alarm_offset_seconds"

@Singleton
class VideoGameSettingsPreferences @Inject constructor(
    private val preferences: Preferences
) {
    fun getAlarmOffset(): GameStartAlarmOffset {
        val seconds = preferences.getInt(KEY_ALARM_OFFSET_SECONDS, GameStartAlarmOffset.DEFAULT.seconds)
        return GameStartAlarmOffset.fromSeconds(seconds)
    }

    fun setAlarmOffset(offset: GameStartAlarmOffset) {
        preferences.putInt(KEY_ALARM_OFFSET_SECONDS, offset.seconds)
    }
}
