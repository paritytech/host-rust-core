package io.paritytech.polkadotapp.feature_videogame_impl.data.notifications

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.GameStartAlarmOffset
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.ProductGameSlot
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

private const val KEY_ALARM_OFFSET_SECONDS = "video_game_alarm_offset_seconds"
private const val KEY_PRODUCT_GAME_SLOTS = "video_game_product_game_slots"

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

    fun getProductGameSlots(): List<ProductGameSlot> = preferences.getString(KEY_PRODUCT_GAME_SLOTS).toSlots()

    fun productGameSlotsFlow(): Flow<List<ProductGameSlot>> = preferences.stringFlow(KEY_PRODUCT_GAME_SLOTS)
        .map { it.toSlots() }
        .distinctUntilChanged()

    fun setProductGameSlots(slots: List<ProductGameSlot>) {
        preferences.putString(KEY_PRODUCT_GAME_SLOTS, slots.takeIf { it.isNotEmpty() }?.let(Json::encodeToString))
    }

    private fun String?.toSlots(): List<ProductGameSlot> =
        this?.let { runCatching { Json.decodeFromString<List<ProductGameSlot>>(it) }.getOrNull() } ?: emptyList()
}
