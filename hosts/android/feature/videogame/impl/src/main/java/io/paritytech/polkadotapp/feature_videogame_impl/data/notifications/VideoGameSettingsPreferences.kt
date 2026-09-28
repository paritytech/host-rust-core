package io.paritytech.polkadotapp.feature_videogame_impl.data.notifications

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import io.paritytech.polkadotapp.feature_products_api.model.ProductId
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.GameStartAlarmOffset
import io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications.ProductGameSlot
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import javax.inject.Inject
import javax.inject.Singleton

private const val KEY_ALARM_OFFSET_SECONDS = "video_game_alarm_offset_seconds"
private const val KEY_PRODUCT_GAME_SLOT = "video_game_product_game_slot"
private const val SLOT_SEPARATOR = '|'

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

    fun getProductGameSlot(): ProductGameSlot? =
        preferences.getString(KEY_PRODUCT_GAME_SLOT)?.toProductGameSlot()

    fun productGameSlotFlow(): Flow<ProductGameSlot?> = preferences.stringFlow(KEY_PRODUCT_GAME_SLOT)
        .map { it?.toProductGameSlot() }
        .distinctUntilChanged()

    fun setProductGameSlot(slot: ProductGameSlot?) {
        val encoded = slot?.let { "${it.productId.value}$SLOT_SEPARATOR${it.startsAtMillis}" }
        preferences.putString(KEY_PRODUCT_GAME_SLOT, encoded)
    }

    private fun String.toProductGameSlot(): ProductGameSlot? {
        val startsAtMillis = substringAfterLast(SLOT_SEPARATOR).toLongOrNull() ?: return null
        return ProductGameSlot(ProductId.fromStoredValue(substringBeforeLast(SLOT_SEPARATOR)), startsAtMillis)
    }
}
