package io.paritytech.polkadotapp.feature_videogame_impl.presentation.notifications

interface VideoGameNotificationsContract {
    fun resolvePermissionRequest(permissionGranted: Boolean)

    fun back()
}
