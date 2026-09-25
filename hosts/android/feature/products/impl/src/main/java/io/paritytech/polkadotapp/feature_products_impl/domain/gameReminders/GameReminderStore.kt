package io.paritytech.polkadotapp.feature_products_impl.domain.gameReminders

import io.paritytech.polkadotapp.common.data.storage.preferences.Preferences
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import timber.log.Timber
import javax.inject.Inject

interface GameReminderStore {
    fun load(): Map<String, GameReminder>

    fun save(reminders: Map<String, GameReminder>)
}

class RealGameReminderStore @Inject constructor(
    private val preferences: Preferences,
) : GameReminderStore {
    private companion object {
        const val KEY = "truapi.gameReminders"
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val serializer = ListSerializer(GameReminder.serializer())

    override fun load(): Map<String, GameReminder> {
        val raw = preferences.getString(KEY) ?: return emptyMap()
        return runCatching { json.decodeFromString(serializer, raw) }
            .onFailure { Timber.w(it, "Dropping unreadable game reminders") }
            .getOrDefault(emptyList())
            .associateBy { it.productId }
    }

    override fun save(reminders: Map<String, GameReminder>) {
        preferences.putString(KEY, json.encodeToString(serializer, reminders.values.toList()))
    }
}
