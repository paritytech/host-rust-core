package io.paritytech.polkadotapp.feature_videogame_impl.domain.notifications

// Each ask prompts only while the app is in the foreground; otherwise it reports what the OS already allows.
interface ProductGameOsAccess {
    suspend fun requestNotifications(): Boolean

    suspend fun requestExactAlarms(): Boolean

    suspend fun requestCalendar(): Boolean
}
