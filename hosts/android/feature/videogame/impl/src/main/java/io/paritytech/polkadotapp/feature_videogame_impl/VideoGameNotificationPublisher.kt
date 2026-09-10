package io.paritytech.polkadotapp.feature_videogame_impl

import io.paritytech.polkadotapp.common.domain.model.Timestamp

interface VideoGameNotificationPublisher {
    fun publishRegistrationOpenedNotification(timestamp: Timestamp)
    fun publishWaitingRoomAvailableNotification()
    fun publishGameAboutToStartNotification()
    fun publishGameStartsSoonNotification()
    fun cancelGameStartNotifications()
}
